import XCTest
@testable import TextCorrectCore

@MainActor
final class StoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testActionStoreCRUD() throws {
        let store = ActionStore(directory: tempDir())
        let action = Action(name: "Fix")
        try store.upsert(action)
        XCTAssertEqual(store.actions.count, 1)
        try store.remove(id: action.id)
        XCTAssertTrue(store.actions.isEmpty)
    }

    func testActionStorePersists() throws {
        let dir = tempDir()
        try ActionStore(directory: dir).upsert(Action(name: "Fix"))
        let reloaded = ActionStore(directory: dir)
        XCTAssertEqual(reloaded.actions.count, 1)
        XCTAssertEqual(reloaded.actions[0].name, "Fix")
    }

    func testSettingsDefaults() {
        let store = SettingsStore(directory: tempDir())
        XCTAssertEqual(store.settings.activeSpeechModelID, "whisper-base")
        XCTAssertEqual(store.settings.llmTimeoutSeconds, 120)
    }

    func testShortcutConflictAcrossActions() throws {
        let appState = AppState(directory: tempDir())
        let combo = KeyCombination(keyCode: 49, modifiers: [.command])

        var first = Action(name: "A")
        first.shortcut = combo
        try appState.upsertAction(first)

        var second = Action(name: "B")
        second.shortcut = combo
        XCTAssertThrowsError(try appState.upsertAction(second))
    }

    func testProviderEndpointNormalization() {
        let provider = Provider(name: "LM Studio", baseURL: "http://localhost:1234/v1/")
        XCTAssertEqual(provider.normalizedBaseURL, "http://localhost:1234/v1")
        XCTAssertEqual(provider.endpoint("chat/completions")?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertTrue(provider.isLocal)
    }
}
