import Foundation
import Observation

@MainActor
@Observable
public final class ProviderStore {
    public var providers: [Provider]
    private let store: JSONStore<[Provider]>
    private let keychain: KeychainService

    public init(directory: URL) {
        self.store = JSONStore(url: directory.appendingPathComponent("providers.json"))
        self.providers = (try? store.load()) ?? []
        self.keychain = KeychainService()
    }

    public func upsert(_ provider: Provider) throws {
        if let i = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[i] = provider
        } else {
            providers.append(provider)
        }
        try save()
    }

    public func remove(id: UUID) throws {
        keychain.delete("provider.\(id.uuidString)")
        providers.removeAll { $0.id == id }
        try save()
    }

    public func provider(byID id: UUID) -> Provider? {
        providers.first { $0.id == id }
    }

    public func apiKey(for id: UUID) -> String? {
        keychain.get("provider.\(id.uuidString)")
    }

    public func setAPIKey(_ value: String, for id: UUID) throws {
        try keychain.set(value, for: "provider.\(id.uuidString)")
    }

    public func save() throws { try store.save(providers) }
}
