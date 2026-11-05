import XCTest
@testable import TextCorrectCore

final class HotkeyRegistryTests: XCTestCase {
    func testMissingModifierRejected() {
        let combo = KeyCombination(keyCode: 49, modifiers: [])
        XCTAssertEqual(HotkeyRegistry.validate(combo, assigned: [:], owner: "a"), .missingModifier)
    }

    func testConflictDetected() {
        let combo = KeyCombination(keyCode: 49, modifiers: [.command])
        let error = HotkeyRegistry.validate(combo, assigned: [combo: "Другое действие"], owner: "a")
        XCTAssertEqual(error, .conflict("Другое действие"))
    }

    func testFreeComboAccepted() {
        let combo = KeyCombination(keyCode: 49, modifiers: [.command])
        XCTAssertNil(HotkeyRegistry.validate(combo, assigned: [:], owner: "a"))
    }

    func testSameOwnerAllowed() {
        let combo = KeyCombination(keyCode: 49, modifiers: [.command])
        XCTAssertNil(HotkeyRegistry.validate(combo, assigned: [combo: "a"], owner: "a"))
    }
}
