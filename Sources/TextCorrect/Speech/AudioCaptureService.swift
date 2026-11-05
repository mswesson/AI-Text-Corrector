import AVFoundation
import Foundation
import TextCorrectCore

/// Writes microphone buffers to a temporary file with a ten-minute limit.
@MainActor
final class AudioCaptureService {
    private var engine: AVAudioEngine?
    private var writer: RecordingWriter?
    private var limit: Task<Void, Never>?
    private var url: URL?
    private var configurationObserver: NSObjectProtocol?

    /// Requests microphone permission and begins recording without retaining audio in memory.
    func start(onLimit: @escaping @MainActor () -> Void) async throws {
        guard engine == nil else { throw SpeechError.unavailable(tr("Запись уже выполняется.")) }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechError.unavailable(tr("Разрешите доступ к микрофону в настройках macOS."))
        }
        try Task.checkCancellation()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.unavailable(tr("Микрофон недоступен."))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TextCorrect-" + UUID().uuidString + ".caf")
        let writer = try RecordingWriter(url: url, format: format)
        self.url = url
        self.writer = writer
        self.engine = engine
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in writer.write(buffer) }
        do { try engine.start() }
        catch { cancel(); throw error }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { _ in
            Task { @MainActor in onLimit() }
        }
        limit = Task {
            do { try await Task.sleep(for: .seconds(600)) } catch { return }
            onLimit()
        }
    }

    /// Finishes and flushes the recording for local transcription.
    func stop() throws -> URL {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        limit?.cancel()
        limit = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        let error = writer?.finish()
        writer = nil
        guard let url else { throw SpeechError.unavailable(tr("Запись не начата.")) }
        self.url = nil
        if let error { try? FileManager.default.removeItem(at: url); throw error }
        return url
    }

    /// Stops audio capture and removes an unfinished temporary recording.
    func cancel() {
        if let file = try? stop() { try? FileManager.default.removeItem(at: file) }
    }
}

private final class RecordingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var error: Error?

    /// Opens a native PCM recording file using the microphone's format.
    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    /// Serializes file writes and remembers failures from the audio callback.
    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard error == nil else { return }
            do { try file?.write(from: buffer) } catch { self.error = error }
        }
    }

    /// Flushes the recording and returns any audio callback error.
    func finish() -> Error? {
        lock.withLock { file = nil; return error }
    }
}
