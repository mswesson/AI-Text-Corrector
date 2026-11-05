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
    /// Treats scenarios with equal names as distinct shortcut owners.
    func testSameNameDoesNotAllowDuplicateShortcut() throws {
        let state = AppState(directory: tempDir())
        let combo = KeyCombination(keyCode: 1, modifiers: [.command])
        try state.upsertAction(Action(name: "Same", shortcut: combo))
        XCTAssertThrowsError(try state.upsertAction(Action(name: "Same", shortcut: combo)))
    }

    /// Allows renaming a scenario without rejecting its existing shortcut.
    func testRenamePreservesShortcut() throws {
        let state = AppState(directory: tempDir())
        var action = Action(name: "Before", shortcut: KeyCombination(keyCode: 1, modifiers: [.command]))
        try state.upsertAction(action)
        action.name = "After"
        try state.upsertAction(action)
        XCTAssertEqual(state.actions.actions.first?.name, "After")
    }

    /// Keeps persisted settings unchanged when macOS rejects a shortcut.
    func testUnavailableShortcutIsNotSaved() {
        let state = AppState(directory: tempDir())
        let original = state.settings.settings.universalShortcut
        state.shortcutAvailability = { _ in false }
        XCTAssertThrowsError(try state.setUniversalShortcut(KeyCombination(keyCode: 1, modifiers: [.command])))
        XCTAssertEqual(state.settings.settings.universalShortcut, original)
    }

}
