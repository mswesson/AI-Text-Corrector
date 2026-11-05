import Foundation

public struct ChatMessage: Codable, Equatable {
    public var role: String
    public var content: String
    public var imageURLs: [String]

    private enum CodingKeys: String, CodingKey { case role, content }

    private struct ContentPart: Codable {
        struct ImageURL: Codable { var url: String }
        var type: String
        var text: String?
        var image_url: ImageURL?
    }

    /// Creates a text message with optional in-memory image data URLs.
    public init(role: String, content: String, imageURLs: [String] = []) {
        self.role = role
        self.content = content
        self.imageURLs = imageURLs
    }

    /// Encodes text-only messages as strings and image messages as content parts.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if imageURLs.isEmpty {
            try container.encode(content, forKey: .content)
        } else {
            var parts: [ContentPart] = content.isEmpty ? [] : [ContentPart(type: "text", text: content)]
            parts += imageURLs.map { ContentPart(type: "image_url", image_url: .init(url: $0)) }
            try container.encode(parts, forKey: .content)
        }
    }

    /// Decodes both plain text and multimodal conversation messages.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
            imageURLs = []
        } else {
            let parts = try container.decode([ContentPart].self, forKey: .content)
            content = parts.compactMap(\.text).joined(separator: "\n")
            imageURLs = parts.compactMap { $0.image_url?.url }
        }
    }
}

public enum LLMError: Error, Equatable {
    case imagesUnsupported
    case invalidURL
    case connection(String)
    case unauthorized
    case modelNotFound
    case rateLimited
    case server(Int)
    case timeout
    case emptyResponse
    case invalidResponse

    public var message: String {
        switch self {
        case .imagesUnsupported: return tr("Выбранная модель не поддерживает изображения. Выберите совместимую модель в настройках провайдера.")
        case .invalidURL: return tr("Некорректный адрес API.")
        case .connection(let detail): return tr("Не удалось подключиться к серверу: ") + detail
        case .unauthorized: return tr("Ошибка авторизации. Проверьте API Key.")
        case .modelNotFound: return tr("Модель не найдена.")
        case .rateLimited: return tr("Слишком много запросов (429).")
        case .server(let code): return String(format: tr("Ошибка сервера (HTTP %ld)."), code)
        case .timeout: return tr("Превышено время ожидания ответа.")
        case .emptyResponse: return tr("Модель вернула пустой ответ.")
        case .invalidResponse: return tr("Некорректный ответ сервера.")
        }
    }
}
