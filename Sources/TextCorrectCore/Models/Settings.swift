import Foundation

public struct Settings: Codable, Equatable {
    public var schemaVersion: Int
    public var universalShortcut: KeyCombination?
    public var captureScreenShortcut: KeyCombination?
    public var pushToTalkShortcut: KeyCombination?
    public var voicePostProcessingEnabled: Bool
    public var voicePostProcessProviderID: UUID?
    public var voicePostProcessModelID: String
    public var voicePostProcessPrompt: String
    public var activeSpeechModelID: String
    public var llmTimeoutSeconds: Int
    public var hasShownCloudConsent: Bool

    public static let defaults = Settings(
        schemaVersion: 1,
        universalShortcut: KeyCombination(keyCode: 49, modifiers: [.command, .shift]), // ⌘⇧Space
        captureScreenShortcut: nil,
        pushToTalkShortcut: nil,
        voicePostProcessingEnabled: false,
        voicePostProcessProviderID: nil,
        voicePostProcessModelID: "",
        voicePostProcessPrompt: "Исправь ошибки и расставь пунктуацию, сохраняя смысл.",
        activeSpeechModelID: "whisper-base",
        llmTimeoutSeconds: 120,
        hasShownCloudConsent: false
    )
}
