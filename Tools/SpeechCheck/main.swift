import Foundation
import TextCorrectCore
import TextCorrectSpeech

/// Exercises pinned local weights against a supplied test recording without network access.
@main
struct SpeechCheck {
    /// Verifies model assets, cancellation and actual transcript content.
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 else {
            throw SpeechError.unavailable("Usage: SpeechCheck manifest.json model-id model-directory audio-file expected-fragment")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let models: [SpeechModel]
        if let catalog = try? JSONDecoder().decode([SpeechModel].self, from: data) { models = catalog }
        else { models = [try JSONDecoder().decode(SpeechModel.self, from: data)] }
        guard let model = models.first(where: { $0.id == arguments[2] }) else { throw SpeechError.unavailable("Model not found") }
        try model.validate()
        let directory = URL(fileURLWithPath: arguments[3], isDirectory: true)
        for asset in model.files { try SpeechModelManager.verify(directory.appendingPathComponent(asset.path), asset: asset) }
        let speech = SpeechRecognitionService()
        let cancellation = SpeechCancellation()
        cancellation.cancel()
        do {
            _ = try await speech.transcribe(file: URL(fileURLWithPath: arguments[4]), model: model, directory: directory, cancellation: cancellation)
            throw SpeechError.unavailable("Cancelled inference returned a result")
        } catch is CancellationError {}
        let start = Date()
        let text = try await speech.transcribe(file: URL(fileURLWithPath: arguments[4]), model: model, directory: directory, cancellation: SpeechCancellation())
        guard text.localizedCaseInsensitiveContains(arguments[5]) else {
            throw SpeechError.unavailable("Expected transcript fragment missing: " + text)
        }
        let duringInference = SpeechCancellation()
        let interrupted = Task {
            try await speech.transcribe(file: URL(fileURLWithPath: arguments[4]), model: model, directory: directory, cancellation: duringInference)
        }
        try await Task.sleep(for: .milliseconds(10))
        duringInference.cancel()
        do {
            _ = try await interrupted.value
            throw SpeechError.unavailable("Late inference result was accepted after cancellation")
        } catch is CancellationError {}
        print("PASS \(model.id): \(text)")
        print(String(format: "Inference elapsed: %.2f seconds", Date().timeIntervalSince(start)))
        await speech.unload()
    }
}
