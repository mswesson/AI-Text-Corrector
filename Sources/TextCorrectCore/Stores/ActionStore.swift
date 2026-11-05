import Foundation
import Observation

@MainActor
@Observable
public final class ActionStore {
    public var actions: [Action]
    private let store: JSONStore<[Action]>

    public init(directory: URL) {
        self.store = JSONStore(url: directory.appendingPathComponent("actions.json"))
        self.actions = (try? store.load()) ?? []
    }

    public func upsert(_ action: Action) throws {
        if let i = actions.firstIndex(where: { $0.id == action.id }) {
            actions[i] = action
        } else {
            actions.append(action)
        }
        try save()
    }

    public func remove(id: UUID) throws {
        actions.removeAll { $0.id == id }
        try save()
    }

    public func duplicate(id: UUID) throws {
        guard let src = actions.first(where: { $0.id == id }) else { return }
        var copy = src
        copy.id = UUID()
        copy.name = src.name + " (copy)"
        copy.shortcut = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        actions.append(copy)
        try save()
    }

    public func action(byID id: UUID) -> Action? {
        actions.first { $0.id == id }
    }

    public func save() throws { try store.save(actions) }
}
