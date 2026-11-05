import Foundation

public enum HotkeyError: Error, Equatable {
    case missingModifier
    case conflict(String)   // owner of the conflicting assignment

    public var message: String {
        switch self {
        case .missingModifier: return "Добавьте хотя бы один модификатор (⌘⌥⌃⇧)."
        case .conflict(let owner): return "Это сочетание уже занято: \(owner)."
        }
    }
}

public enum HotkeyRegistry {
    /// Validates `combo` against currently assigned combinations.
    /// `owner` identifies what is being assigned (allows re-assigning the same combo to itself).
    public static func validate(
        _ combo: KeyCombination,
        assigned: [KeyCombination: String],
        owner: String
    ) -> HotkeyError? {
        guard combo.hasModifier else { return .missingModifier }
        if let other = assigned[combo], other != owner {
            return .conflict(other)
        }
        return nil
    }
}
