import AppKit
import ApplicationServices
import Observation
import TextCorrectCore
import TextCorrectSpeech

/// Coordinates microphone, local speech, optional LLM and validated insertion.
@MainActor
@Observable
final class VoiceInputCoordinator {
    enum Phase: Equatable {
        case idle, preparing, recording, transcribing, postprocessing, inserting, completed
        case error(String)
    }
    private(set) var phase: Phase = .idle
    private(set) var result = ""
    private(set) var rawTranscript = ""
    private(set) var isPushToTalk = false
    var isBusy: Bool { operation != nil || phase == .recording }
    private let appState: AppState
    private let audio = AudioCaptureService()
    private let speech = SpeechRecognitionService()
    private let replacement = TextReplacementService()
    private var cancellation = SpeechCancellation()
    private var operation: Task<Void, Never>?
    private var recordingFile: URL?
    private var generation = UUID()
    private var target: SelectionService.Captured?
    private var model: SpeechModel?
    private var modelDirectory: URL?
    private var settings = Settings.defaults
    private var onText: ((String) -> Void)?

    /// Connects voice operations to installed models and saved preferences.
    init(appState: AppState) { self.appState = appState }

    /// Starts palette dictation without invoking LLM or inserting into another app.
    func startPalette(onText: @escaping (String) -> Void) {
        begin(target: nil, pushToTalk: false, onText: onText)
    }

    /// Captures the original cursor before starting global dictation.
    func startPushToTalk() {
        guard !isBusy else { return }
        guard AXIsProcessTrusted() else {
            isPushToTalk = true
            result = ""
            rawTranscript = ""
            phase = .error(tr("Разрешите универсальный доступ в настройках macOS для безопасной вставки диктовки."))
            return
        }
        begin(target: SelectionService().capture(allowEmpty: true), pushToTalk: true, onText: nil)
    }

    /// Stops a recording and begins local inference exactly once.
    func finishRecording() {
        guard phase == .recording, let model, let modelDirectory else {
            if phase == .preparing { cancel() }
            return
        }
        do {
            let file = try audio.stop()
            recordingFile = file
            phase = .transcribing
            let id = generation
            operation = Task {
                defer {
                    try? FileManager.default.removeItem(at: file)
                    recordingFile = nil
                    releaseModel()
                    operation = nil
                }
                do {
                    let text = try await speech.transcribe(file: file, model: model, directory: modelDirectory, cancellation: cancellation)
                    try? FileManager.default.removeItem(at: file)
                    recordingFile = nil
                    guard generation == id, !Task.isCancelled else { return }
                    rawTranscript = text
                    result = text
                    if isPushToTalk {
                        if settings.voicePostProcessingEnabled {
                            phase = .postprocessing
                            let provider = settings.voicePostProcessProviderID.flatMap { appState.providers.provider(byID: $0) }
                            let processor = VoicePostprocessor(client: LLMClient(timeout: TimeInterval(settings.llmTimeoutSeconds)))
                            let processed = try await processor.process(text, settings: settings, provider: provider,
                                apiKey: provider.flatMap { appState.providers.apiKey(for: $0.id) })
                            guard generation == id, !Task.isCancelled else { return }
                            result = processed
                        }
                        guard generation == id, !Task.isCancelled else { return }
                        insertResult(automatic: true)
                    } else {
                        onText?(text)
                        phase = .completed
                    }
                } catch is CancellationError {
                    if generation == id { phase = .idle }
                } catch {
                    guard generation == id else { return }
                    phase = .error((error as? LLMError)?.message ?? error.localizedDescription)
                }
            }
        } catch { releaseModel(); phase = .error(error.localizedDescription) }
    }

    /// Cancels recording, inference and postprocessing while preventing late insertion.
    func cancel() {
        generation = UUID()
        cancellation.cancel()
        operation?.cancel()
        audio.cancel()
        if let recordingFile { try? FileManager.default.removeItem(at: recordingFile) }
        recordingFile = nil
        if operation == nil { releaseModel() }
        phase = .idle
        onText = nil
        result = ""
        rawTranscript = ""
    }

    /// Inserts an explicitly selected result only into the validated saved target.
    func insertResult(automatic: Bool = false) {
        guard !result.isEmpty, let target else {
            phase = .error(tr("Исходное поле недоступно. Скопируйте результат."))
            return
        }
        phase = .inserting
        switch replacement.replace(target, with: result, requireFrontmost: automatic) {
        case .replaced: phase = .completed
        case .failed(let reason): phase = .error(reason.message + tr(" Скопируйте результат."))
        }
    }

    /// Uses the retained raw transcript only after an explicit user action.
    func insertRawTranscript() {
        result = rawTranscript
        insertResult()
    }

    /// Reserves an installed model before microphone permission can suspend execution.
    private func begin(target: SelectionService.Captured?, pushToTalk: Bool, onText: ((String) -> Void)?) {
        guard !isBusy else { return }
        isPushToTalk = pushToTalk
        result = ""
        rawTranscript = ""
        self.target = target
        self.onText = onText
        settings = appState.settings.settings
        do {
            let (model, directory) = try appState.speechModels.activeModel()
            self.model = model
            modelDirectory = directory
            appState.speechModels.inUse.insert(model.id)
        } catch { phase = .error(error.localizedDescription); return }
        cancellation = SpeechCancellation()
        generation = UUID()
        let id = generation
        phase = .preparing
        operation = Task {
            defer {
                operation = nil
                if generation != id { releaseModel() }
            }
            do {
                try await audio.start { [weak self = self] in self?.finishRecording() }
                guard generation == id, !Task.isCancelled else { return }
                phase = .recording
            } catch {
                guard generation == id else { return }
                releaseModel()
                phase = .error(error.localizedDescription)
            }
        }
    }

    /// Releases the model reservation once an operation has stopped using its files.
    private func releaseModel() {
        if let model { appState.speechModels.inUse.remove(model.id) }
        model = nil
        modelDirectory = nil
    }
}
