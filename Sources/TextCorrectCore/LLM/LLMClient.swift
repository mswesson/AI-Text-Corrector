import Foundation

struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool = false
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String? }
        var message: Message
    }
    var choices: [Choice]
}

struct ModelListResponse: Decodable {
    struct Item: Decodable { var id: String }
    var data: [Item]
}

/// Asynchronous OpenAI-compatible Chat Completions client.
public final class LLMClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 120) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    public func complete(_ provider: Provider, model: String, messages: [ChatMessage], apiKey: String?) async throws -> String {
        guard let url = provider.endpoint("chat/completions") else { throw LLMError.invalidURL }
        let request = try makeRequest(url: url, body: ChatRequest(model: model, messages: messages), apiKey: apiKey)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw Self.map(urlError)
        }
        try Self.checkHTTP(response)
        return try Self.parse(data)
    }

    public func listModels(_ provider: Provider, apiKey: String?) async throws -> [String] {
        guard let url = provider.endpoint("models") else { throw LLMError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        Self.applyAuth(&request, apiKey: apiKey)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw Self.map(urlError)
        }
        try Self.checkHTTP(response)
        guard let list = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
            throw LLMError.invalidResponse
        }
        return list.data.map(\.id)
    }

    // MARK: - Helpers

    private func makeRequest<T: Encodable>(url: URL, body: T, apiKey: String?) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuth(&request, apiKey: apiKey)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func applyAuth(_ request: inout URLRequest, apiKey: String?) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    static func map(_ error: URLError) -> Error {
        if error.code == .cancelled { return CancellationError() }
        if error.code == .timedOut { return LLMError.timeout }
        return LLMError.connection(error.localizedDescription)
    }

    static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw LLMError.unauthorized
        case 404: throw LLMError.modelNotFound
        case 429: throw LLMError.rateLimited
        default: throw LLMError.server(http.statusCode)
        }
    }

    static func parse(_ data: Data) throws -> String {
        let response: ChatResponse
        do {
            response = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }
        guard let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }
}
