import AppKit
import ApplicationServices
import TextCorrectCore

/// Replaces the original selection only after re-validating the saved snapshot.
@MainActor
final class TextReplacementService {
    enum Result: Equatable {
        case replaced
        case failed(TargetCheck)
    }

    private let selection = SelectionService()

    /// Replaces only the original AX element after validating its current selection.
    func replace(_ captured: SelectionService.Captured, with text: String, requireFrontmost: Bool = false) -> Result {
        guard AXIsProcessTrusted() else { return .failed(.elementUnavailable) }
        let saved = captured.context
        guard !text.isEmpty else { return .failed(.selectionChanged) }
        if requireFrontmost, NSWorkspace.shared.frontmostApplication?.processIdentifier != saved.pid {
            return .failed(.elementUnavailable)
        }
        let app = NSRunningApplication(processIdentifier: saved.pid)
        let appElement = AXUIElementCreateApplication(saved.pid)
        let focused = selection.elementAttribute(appElement, kAXFocusedUIElementAttribute)
        let check = ReplacementValidator.check(
            saved: saved,
            isAppRunning: app != nil && app?.isTerminated == false,
            currentRole: focused.flatMap { selection.stringAttribute($0, kAXRoleAttribute) },
            currentSelectedText: focused.flatMap { selection.stringAttribute($0, kAXSelectedTextAttribute) },
            currentFieldValue: focused.flatMap { selection.stringAttribute($0, kAXValueAttribute) },
            currentRange: focused.flatMap { selection.rangeAttribute($0, kAXSelectedTextRangeAttribute) },
            isSameElement: focused.map { current in
                captured.element.map { CFEqual(current, $0) } ?? false
            } ?? false
        )
        guard check == .safe, let focused else { return .failed(check) }
        guard AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return .failed(.elementUnavailable)
        }
        app?.activate()
        return .replaced
    }
}
