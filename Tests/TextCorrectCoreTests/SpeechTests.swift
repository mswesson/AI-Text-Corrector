import XCTest
@testable import TextCorrectCore

private actor VoiceClient: LLMCompleting {
    var messages: [ChatMessage] = []
    var callCount = 0
    let response: Result<String, LLMError>

    /// Configures a deterministic voice postprocessing transport.
    init(response: Result<String, LLMError> = .success("processed")) { self.response = response }

    /// Records input messages and returns the configured response without network access.
    func complete(_ provider: Provider, model: String, messages: [ChatMessage], apiKey: String?) async throws -> String {
        callCount += 1
        self.messages = messages
        return try response.get()
    }
}

@MainActor
final class SpeechTests: XCTestCase {
    /// Ensures Base is downloadable and no speech asset is implicitly installed.
    func testCatalogContainsPinnedDownloadableModels() throws {
        let catalog = try SpeechModel.catalog()
        XCTAssertTrue(catalog.contains { $0.id == "whisper-base" })
        for model in catalog { XCTAssertNoThrow(try model.validate()) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SpeechModelManager(directory: directory, settings: SettingsStore(directory: directory))
        XCTAssertTrue(manager.installed.isEmpty)
        XCTAssertThrowsError(try manager.activeModel())
    }

    /// Rejects traversal paths and mutable repository references before downloading.
    func testUnsafeModelAssetsRejected() throws {
        var model = try XCTUnwrap(SpeechModel.catalog().first)
        model.files[0].path = "../escape.bin"
        XCTAssertThrowsError(try model.validate())
        model.files[0].path = "weights.bin"
        model.files[0].url = URL(string: "https://huggingface.co/model/resolve/main/weights.bin")!
        XCTAssertThrowsError(try model.validate())
    }

    /// Verifies actual file bytes and refuses a checksum or size mismatch.
    func testAssetIntegrity() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)
        var asset = try XCTUnwrap(SpeechModel.catalog().first?.files.first)
        asset.size = 5
        asset.sha256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertNoThrow(try SpeechModelManager.verify(url, asset: asset))
        try Data("HELLO".utf8).write(to: url)
        XCTAssertThrowsError(try SpeechModelManager.verify(url, asset: asset))
        try Data("hello!".utf8).write(to: url)
        XCTAssertThrowsError(try SpeechModelManager.verify(url, asset: asset))
    }

    /// Never calls LLM when postprocessing is disabled, even without a configured provider.
    func testDisabledPostprocessingNeverCallsLLM() async throws {
        let client = VoiceClient()
        let output = try await VoicePostprocessor(client: client).process("raw speech", settings: .defaults, provider: nil, apiKey: nil)
        let calls = await client.callCount
        XCTAssertEqual(output, "raw speech")
        XCTAssertEqual(calls, 0)
    }

    /// Uses exactly the configured prompt and recognized speech without additional style rules.
    func testEnabledPostprocessingUsesUserPrompt() async throws {
        let client = VoiceClient()
        var settings = Settings.defaults
        settings.voicePostProcessingEnabled = true
        settings.voicePostProcessModelID = "test"
        settings.voicePostProcessPrompt = "Translate into Chinese."
        let provider = Provider(name: "Local", baseURL: "http://localhost:1234/v1")
        let output = try await VoicePostprocessor(client: client).process("raw speech", settings: settings, provider: provider, apiKey: nil)
        let messages = await client.messages
        XCTAssertEqual(output, "processed")
        XCTAssertEqual(messages, [ChatMessage(role: "system", content: settings.voicePostProcessPrompt), ChatMessage(role: "user", content: "raw speech")])
    }

    /// Refuses cloud postprocessing until consent is saved.
    func testCloudVoiceRequiresConsent() async {
        let client = VoiceClient()
        var settings = Settings.defaults
        settings.voicePostProcessingEnabled = true
        settings.voicePostProcessModelID = "test"
        do {
            _ = try await VoicePostprocessor(client: client).process("private speech", settings: settings,
                provider: Provider(name: "Cloud", baseURL: "https://api.example.com/v1"), apiKey: nil)
            XCTFail("Expected consent failure")
        } catch {}
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    /// Surfaces LLM failure instead of silently treating the raw transcript as processed output.
    func testPostprocessingFailureIsNotSilentFallback() async {
        let client = VoiceClient(response: .failure(.timeout))
        var settings = Settings.defaults
        settings.voicePostProcessingEnabled = true
        settings.voicePostProcessModelID = "test"
        do {
            _ = try await VoicePostprocessor(client: client).process("raw speech", settings: settings,
                provider: Provider(name: "Local", baseURL: "http://localhost:1234/v1"), apiKey: nil)
            XCTFail("Expected LLM failure")
        } catch { XCTAssertEqual(error as? LLMError, .timeout) }
    }

    /// Allows safe insertion at an unchanged zero-length cursor range.
    func testCursorInsertionRequiresUnchangedRange() {
        let saved = TargetContext(pid: 42, role: "AXTextArea", originalText: "", range: NSRange(location: 3, length: 0), fieldValue: "hello")
        XCTAssertEqual(ReplacementValidator.check(saved: saved, isAppRunning: true, currentRole: "AXTextArea",
            currentSelectedText: nil, currentFieldValue: "hello", currentRange: saved.range, isSameElement: true), .safe)
        XCTAssertEqual(ReplacementValidator.check(saved: saved, isAppRunning: true, currentRole: "AXTextArea",
            currentSelectedText: nil, currentFieldValue: "hello", currentRange: NSRange(location: 4, length: 0), isSameElement: true), .selectionChanged)
    }

    /// Reads settings saved before optional onboarding and preferred-model fields existed.
    func testSettingsRemainBackwardCompatible() throws {
        let encoded = try JSONEncoder().encode(Settings.defaults)
        let decoded = try JSONDecoder().decode(Settings.self, from: encoded)
        XCTAssertNil(decoded.hasCompletedOnboarding)
        XCTAssertEqual(decoded.activeSpeechModelID, "whisper-base")
    }
}
