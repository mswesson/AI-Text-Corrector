import Foundation

/// A saved AI scenario: a system prompt + a model + an optional shortcut.
public struct Action: Codable, Identifiable, Equatable {
    public enum Mode: String, Codable { case chat, transform }

    public var id: UUID
    public var name: String
    public var description: String?
    public var mode: Mode
    public var systemPrompt: String
    public var providerID: UUID?
    public var modelID: String
    public var shortcut: KeyCombination?
    public var requiresSelection: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        mode: Mode = .transform,
        systemPrompt: String = "",
        providerID: UUID? = nil,
        modelID: String = "",
        shortcut: KeyCombination? = nil,
        requiresSelection: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.shortcut = shortcut
        self.requiresSelection = requiresSelection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
