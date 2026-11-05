import Foundation

/// Applies only the optional, user-authored voice transformation.
public struct VoicePostprocessor {
    private let client: any LLMCompleting

    /// Creates a postprocessor with an injectable LLM transport.
    public init(client: any LLMCompleting = LLMClient()) { self.client = client }

    /// Returns raw STT when disabled and otherwise applies the configured system prompt.
    public func process(_ text: String, settings: Settings, provider: Provider?, apiKey: String?) async throws -> String {
        guard settings.voicePostProcessingEnabled else { return text }
        guard let provider, !settings.voicePostProcessModelID.isEmpty else {
            throw SpeechError.unavailable(tr("Выберите провайдера и модель постобработки в Voice Input."))
        }
        guard provider.isLocal || settings.hasShownCloudConsent else {
            throw SpeechError.unavailable(tr("Разрешите облачную постобработку в настройках Voice Input."))
        }
        let result = try await client.complete(provider, model: settings.voicePostProcessModelID,
            messages: RequestBuilder.initialTransform(systemPrompt: settings.voicePostProcessPrompt, text: text), apiKey: apiKey)
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.emptyResponse }
        return result
    }
}
