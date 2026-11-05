import Foundation

/// An OpenAI-compatible LLM endpoint. The API key lives in Keychain, not here.
public struct Provider: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var baseURL: String      // e.g. http://localhost:1234/v1
    public var models: [String]
    public var supportsVision: Bool
    public var visionModelIDs: [String]?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        models: [String] = [],
        supportsVision: Bool = false,
        visionModelIDs: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
        self.supportsVision = supportsVision
        self.visionModelIDs = visionModelIDs
        self.createdAt = createdAt
    }

    /// Checks model-specific image support while preserving older provider settings.
    public func supportsImages(model: String) -> Bool {
        visionModelIDs?.contains(model) ?? supportsVision
    }

    public var normalizedBaseURL: String {
        baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func endpoint(_ path: String) -> URL? {
        URL(string: "\(normalizedBaseURL)/\(path)")
    }

    public var isLocal: Bool {
        let host = endpoint("")?.host?.lowercased() ?? ""
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
