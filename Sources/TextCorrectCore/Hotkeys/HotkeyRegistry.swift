import Foundation

public enum HotkeyError: Error, Equatable {
    case systemUnavailable
    case missingModifier
    case conflict(String)   // owner of the conflicting assignment

    public var message: String {
        switch self {
        case .systemUnavailable: return tr("macOS не разрешила зарегистрировать сочетание. Выберите другое.")
        case .missingModifier: return tr("Добавьте хотя бы один модификатор (⌘⌥⌃⇧).")
        case .conflict(let owner): return tr("Это сочетание уже занято: ") + owner + "."
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
