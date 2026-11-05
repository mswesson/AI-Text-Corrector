import XCTest
@testable import TextCorrectCore

final class TargetContextTests: XCTestCase {
    private func saved(source: TargetContext.Source = .accessibility) -> TargetContext {
        TargetContext(
            pid: 42,
            role: "AXTextArea",
            originalText: "hello",
            range: NSRange(location: 0, length: 5),
            fieldValue: "hello",
            source: source
        )
    }

    func testSafeWhenTextMatches() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: true,
            currentRole: "AXTextArea", currentSelectedText: "hello", currentFieldValue: "hello", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(check, .safe)
    }

    func testAppClosed() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: false,
            currentRole: "AXTextArea", currentSelectedText: "hello", currentFieldValue: "hello", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(check, .appUnavailable)
    }

    func testElementLost() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: true,
            currentRole: nil, currentSelectedText: nil, currentFieldValue: nil, currentRange: nil, isSameElement: false
        )
        XCTAssertEqual(check, .elementUnavailable)
    }

    func testRoleChanged() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: true,
            currentRole: "AXTextField", currentSelectedText: "hello", currentFieldValue: "hello", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(check, .roleChanged)
    }

    func testSelectionChanged() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: true,
            currentRole: "AXTextArea", currentSelectedText: "bye", currentFieldValue: "bye", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(check, .selectionChanged)
    }

    func testSelectionCleared() {
        let check = ReplacementValidator.check(
            saved: saved(), isAppRunning: true,
            currentRole: "AXTextArea", currentSelectedText: "", currentFieldValue: "hello", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(check, .selectionChanged)
    }

    func testClipboardSourceCannotAuthorizeReplacement() {
        let ok = ReplacementValidator.check(
            saved: saved(source: .clipboard), isAppRunning: true,
            currentRole: "AXTextArea", currentSelectedText: nil, currentFieldValue: "hello", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(ok, .selectionChanged)

        let changed = ReplacementValidator.check(
            saved: saved(source: .clipboard), isAppRunning: true,
            currentRole: "AXTextArea", currentSelectedText: nil, currentFieldValue: "hello world", currentRange: NSRange(location: 0, length: 5), isSameElement: true
        )
        XCTAssertEqual(changed, .selectionChanged)
    }
    /// Rejects another field even when its selected text is identical.
    func testDifferentElementRejected() {
        XCTAssertEqual(ReplacementValidator.check(
            saved: saved(), isAppRunning: true, currentRole: "AXTextArea",
            currentSelectedText: "hello", currentFieldValue: "hello",
            currentRange: NSRange(location: 0, length: 5), isSameElement: false
        ), .elementUnavailable)
    }

    /// Rejects an identical word selected at another position.
    func testMovedRangeRejected() {
        XCTAssertEqual(ReplacementValidator.check(
            saved: saved(), isAppRunning: true, currentRole: "AXTextArea",
            currentSelectedText: "hello", currentFieldValue: "hello",
            currentRange: NSRange(location: 10, length: 5), isSameElement: true
        ), .selectionChanged)
    }

    /// Rejects a changed document even when its selection still matches.
    func testChangedFieldRejected() {
        XCTAssertEqual(ReplacementValidator.check(
            saved: saved(), isAppRunning: true, currentRole: "AXTextArea",
            currentSelectedText: "hello", currentFieldValue: "hello world",
            currentRange: NSRange(location: 0, length: 5), isSameElement: true
        ), .selectionChanged)
    }

}
