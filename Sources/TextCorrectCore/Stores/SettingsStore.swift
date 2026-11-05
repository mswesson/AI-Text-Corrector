import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public var settings: Settings
    private let store: JSONStore<Settings>

    public init(directory: URL) {
        self.store = JSONStore(url: directory.appendingPathComponent("settings.json"))
        self.settings = (try? store.load()) ?? .defaults
    }

    public func save() throws { try store.save(settings) }
}
