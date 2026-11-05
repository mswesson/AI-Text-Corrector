import Foundation
import Observation

/// Composition root: owns the stores and enforces global shortcut uniqueness.
@MainActor
@Observable
public final class AppState {
    public let actions: ActionStore
    public let providers: ProviderStore
    public let settings: SettingsStore

    nonisolated public static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TextCorrect", isDirectory: true)
    }

    public init(directory: URL = AppState.supportDirectory()) {
        self.actions = ActionStore(directory: directory)
        self.providers = ProviderStore(directory: directory)
        self.settings = SettingsStore(directory: directory)
    }

    // MARK: - Shortcuts

    public func upsertAction(_ action: Action) throws {
        if let combo = action.shortcut {
            try validate(combo, owner: owner(for: action))
        }
        try actions.upsert(action)
    }

    public func setUniversalShortcut(_ combo: KeyCombination?) throws {
        if let combo { try validate(combo, owner: "Универсальный хоткей") }
        settings.settings.universalShortcut = combo
        try settings.save()
    }

    public func setCaptureShortcut(_ combo: KeyCombination?) throws {
        if let combo { try validate(combo, owner: "Захват экрана") }
        settings.settings.captureScreenShortcut = combo
        try settings.save()
    }

    public func setPushToTalkShortcut(_ combo: KeyCombination?) throws {
        if let combo { try validate(combo, owner: "Push-to-Talk") }
        settings.settings.pushToTalkShortcut = combo
        try settings.save()
    }

    private func owner(for action: Action) -> String {
        "Сценарий «\(action.name)»"
    }

    private func assignedShortcuts() -> [KeyCombination: String] {
        var map: [KeyCombination: String] = [:]
        if let c = settings.settings.universalShortcut { map[c] = "Универсальный хоткей" }
        if let c = settings.settings.captureScreenShortcut { map[c] = "Захват экрана" }
        if let c = settings.settings.pushToTalkShortcut { map[c] = "Push-to-Talk" }
        for a in actions.actions {
            if let shortcut = a.shortcut { map[shortcut] = owner(for: a) }
        }
        return map
    }

    private func validate(_ combo: KeyCombination, owner: String) throws {
        if let error = HotkeyRegistry.validate(combo, assigned: assignedShortcuts(), owner: owner) {
            throw error
        }
    }
}
