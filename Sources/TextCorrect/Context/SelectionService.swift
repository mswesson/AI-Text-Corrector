import AppKit
import ApplicationServices
import TextCorrectCore

/// Reads the current selection from the frontmost app and keeps the AX element for later replacement.
@MainActor
final class SelectionService {
    struct Captured {
        var context: TargetContext
        var element: AXUIElement?
        var appElement: AXUIElement?
    }

    private let secureRoles: Set<String> = [
        "AXSecureTextField", "AXSecureTextArea",
    ]

    /// Captures only a readable, nonsecure focused text selection.
    func capture(allowEmpty: Bool = false) -> Captured? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute)

        let role = focused.flatMap { stringAttribute($0, kAXRoleAttribute) }
        guard let focused, let role, !secureRoles.contains(role),
              stringAttribute(focused, kAXSubroleAttribute) != kAXSecureTextFieldSubrole else {
            return nil
        }

        let range = rangeAttribute(focused, kAXSelectedTextRangeAttribute)
        let text = stringAttribute(focused, kAXSelectedTextAttribute) ?? (range?.length == 0 ? "" : nil)
        let fieldValue = stringAttribute(focused, kAXValueAttribute)
        guard let text, allowEmpty || !text.isEmpty,
              !allowEmpty || (range != nil && fieldValue != nil) else { return nil }

        let context = TargetContext(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName,
            role: role,
            originalText: text,
            range: range,
            fieldValue: fieldValue,
            source: .accessibility
        )
        return Captured(context: context, element: focused, appElement: appElement)
    }

    // MARK: - AX helpers

    /// Reads an Accessibility element attribute with type validation.
    func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Reads a string attribute from an Accessibility element.
    func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Reads a UTF-16 selection range from an Accessibility element.
    func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
