import Foundation

/// One physical key plus a set of modifier keys.
public struct KeyCombination: Codable, Hashable, Identifiable {
    public enum Modifier: String, Codable, Hashable, CaseIterable {
        case control, option, shift, command
    }

    public var keyCode: UInt16
    public var modifiers: Set<Modifier>

    public init(keyCode: UInt16, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var id: String {
        let mods = modifiers.map(\.rawValue).sorted().joined(separator: "+")
        return "\(keyCode)-\(mods)"
    }

    public var hasModifier: Bool { !modifiers.isEmpty }
}
