import Foundation
import AVFoundation
import FluidAudio
import TextCorrectCore
import whisper

/// Shares cancellation with native inference callbacks without racing the UI.
public final class SpeechCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public var isCancelled: Bool { lock.withLock { cancelled } }

    /// Creates a cancellation flag for one speech request.
    public init() {}

    /// Marks the current native inference as cancelled.
    public func cancel() { lock.withLock { cancelled = true } }
}

/// Runs one local engine at a time and unloads idle model weights.
public actor SpeechRecognitionService {
    private var whisper: WhisperEngine?
    private var parakeet: AsrManager?
    private var loadedPath: String?
    private var idleTask: Task<Void, Never>?

    /// Creates a speech runtime without loading model weights.
    public init() {}

    /// Transcribes a recording in bounded chunks using the selected installed model.
    public func transcribe(file: URL, model: SpeechModel, directory: URL, cancellation: SpeechCancellation) async throws -> String {
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
        idleTask?.cancel()
        defer {
            idleTask = Task {
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                unload()
            }
        }
        if loadedPath != directory.path {
            unload()
            switch model.engine {
            case .whisper:
                whisper = try WhisperEngine(url: directory.appendingPathComponent(model.files[0].path))
            case .parakeet:
                let manager = AsrManager()
                let models = try AsrModels.loadLocal(from: directory, version: .v3)
                try await manager.loadModels(models)
                parakeet = manager
            }
            loadedPath = directory.path
        }
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
        let reader = try AudioFileReader(url: file)
        var parts: [String] = []
        while let samples = try reader.nextSamples() {
            if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
            let energy = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(samples.count, 1))
            if energy < 0.00000001 { continue }
            let text: String
            if let whisper {
                text = try whisper.transcribe(samples, cancellation: cancellation)
            } else if let parakeet {
                var decoder = try TdtDecoderState()
                text = try await parakeet.transcribe(samples, decoderState: &decoder).text
            } else { throw SpeechError.unavailable(tr("Модель не загружена.")) }
            if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
            parts.append(text)
        }
        let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SpeechError.noSpeech }
        return text
    }

    /// Releases cached weights before switching engines or after an idle interval.
    public func unload() {
        whisper = nil
        parakeet = nil
        loadedPath = nil
    }
}

private final class WhisperEngine {
    private let context: OpaquePointer

    /// Loads pinned GGML weights into whisper.cpp with Metal acceleration.
    init(url: URL) throws {
        whisper_log_set({ _, _, _ in }, nil)
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        guard let context = whisper_init_from_file_with_params(url.path, parameters) else {
            throw SpeechError.unavailable(tr("Не удалось загрузить Whisper. Проверьте файлы модели."))
        }
        self.context = context
    }

    /// Releases native model memory when its cached engine is discarded.
    deinit { whisper_free(context) }

    /// Transcribes one mono 16 kHz chunk and checks the native cancellation flag.
    func transcribe(_ samples: [Float], cancellation: SpeechCancellation) throws -> String {
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.n_threads = Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.no_context = true
        parameters.no_timestamps = true
        parameters.language = nil
        parameters.abort_callback = { pointer in
            guard let pointer else { return false }
            return Unmanaged<SpeechCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }
        parameters.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        let status = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
        }
        if cancellation.isCancelled { throw CancellationError() }
        guard status == 0 else { throw SpeechError.unavailable(tr("Ошибка локального распознавания Whisper.")) }
        return (0..<whisper_full_n_segments(context)).compactMap { index in
            whisper_full_get_segment_text(context, index).map { String(cString: $0) }
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class AudioFileReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer

    /// Opens an audio file for streaming conversion to mono 16 kHz Float32 PCM.
    init(url: URL) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000) else {
            throw SpeechError.unavailable(tr("Неподдерживаемый аудиоформат."))
        }
        self.converter = converter
        self.input = input
        self.output = output
    }

    /// Reads at most thirty seconds without retaining the rest of a long recording.
    func nextSamples() throws -> [Float]? {
        output.frameLength = 0
        var conversionError: NSError?
        var readError: Error?
        let status = converter.convert(to: output, error: &conversionError) { [self] count, inputStatus in
            guard file.framePosition < file.length else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: input, frameCount: min(count, input.frameCapacity))
                inputStatus.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                return input.frameLength == 0 ? nil : input
            } catch {
                readError = error
                inputStatus.pointee = .endOfStream
                return nil
            }
        }
        if let readError { throw readError }
        if status == .error { throw conversionError ?? NSError(domain: "AudioConversion", code: 1) }
        guard output.frameLength > 0, let data = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
