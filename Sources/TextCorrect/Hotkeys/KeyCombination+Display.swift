import AppKit
import CoreGraphics
import Foundation
import TextCorrectCore

extension KeyCombination {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = Set<Modifier>()
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift)   { mods.insert(.shift) }
        if flags.contains(.option)  { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        self.init(keyCode: event.keyCode, modifiers: mods)
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    /// Gives special keys a readable name before consulting the current keyboard layout.
    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "⏎"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: break
        }
        var buffer = [UniChar](repeating: 0, count: 4)
        var actual = 0
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            buffer.withUnsafeMutableBufferPointer { ptr in
                event.keyboardGetUnicodeString(
                    maxStringLength: 4,
                    actualStringLength: &actual,
                    unicodeString: ptr.baseAddress
                )
            }
        }
        if actual > 0 {
            let text = String(utf16CodeUnits: buffer, count: actual)
            if !text.isEmpty { return text.uppercased() }
        }
        return "⌨\(keyCode)"
    }
}
