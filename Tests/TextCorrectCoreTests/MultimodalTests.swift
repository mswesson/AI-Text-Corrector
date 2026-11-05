import XCTest
@testable import TextCorrectCore

final class MultimodalTests: XCTestCase {
    /// Keeps the wire format unchanged for plain text providers.
    func testPlainTextRequestUsesStringContent() throws {
        let request = ChatRequest(model: "text", messages: [ChatMessage(role: "user", content: "hello")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, "hello")
    }

    /// Encodes text and multiple images as standard Chat Completions content parts.
    func testImageRequestContainsDataURLs() throws {
        let urls = ["data:image/png;base64,YQ==", "data:image/png;base64,Yg=="]
        let message = ChatMessage(role: "user", content: "explain", imageURLs: urls)
        let data = try JSONEncoder().encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try XCTUnwrap(json["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "explain")
        for index in urls.indices {
            XCTAssertEqual(parts[index + 1]["type"] as? String, "image_url")
            XCTAssertEqual((parts[index + 1]["image_url"] as? [String: String])?["url"], urls[index])
        }
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: data), message)
    }

    /// Allows a request containing an image without an empty text part.
    func testImageOnlyRequest() throws {
        let message = ChatMessage(role: "user", content: "", imageURLs: ["data:image/png;base64,YQ=="])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let parts = try XCTUnwrap(json["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0]["type"] as? String, "image_url")
    }

    /// Preserves older provider files and lets per-model settings override the legacy flag.
    func testProviderCompatibilityAndModelCapabilities() throws {
        let oldProvider = Provider(name: "Legacy", baseURL: "http://localhost:1234/v1", supportsVision: true)
        let encoded = try JSONEncoder().encode(oldProvider)
        let decoded = try JSONDecoder().decode(Provider.self, from: encoded)
        XCTAssertTrue(decoded.supportsImages(model: "legacy"))
        var mixed = decoded
        mixed.visionModelIDs = ["vision"]
        XCTAssertTrue(mixed.supportsImages(model: "vision"))
        XCTAssertFalse(mixed.supportsImages(model: "text"))
    }
}
