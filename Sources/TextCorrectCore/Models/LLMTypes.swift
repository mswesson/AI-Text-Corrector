import Foundation

public struct ChatMessage: Codable, Equatable {
    public var role: String   // "system" | "user" | "assistant"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum LLMError: Error, Equatable {
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
        case .invalidURL: return "Некорректный адрес API."
        case .connection(let detail): return "Не удалось подключиться к серверу: \(detail)"
        case .unauthorized: return "Ошибка авторизации. Проверьте API Key."
        case .modelNotFound: return "Модель не найдена."
        case .rateLimited: return "Слишком много запросов (429)."
        case .server(let code): return "Ошибка сервера (HTTP \(code))."
        case .timeout: return "Превышено время ожидания ответа."
        case .emptyResponse: return "Модель вернула пустой ответ."
        case .invalidResponse: return "Некорректный ответ сервера."
        }
    }
}
