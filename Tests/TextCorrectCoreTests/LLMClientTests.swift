import XCTest
@testable import TextCorrectCore

final class LLMClientTests: XCTestCase {
    /// Maps actionable HTTP failures while accepting successful responses.
    func testHTTPErrorMapping() throws {
        let cases: [(Int, LLMError)] = [(401, .unauthorized), (403, .unauthorized), (404, .modelNotFound), (429, .rateLimited), (500, .server(500))]
        let url = URL(string: "http://localhost:1234/v1")!
        for (code, expected) in cases {
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try LLMClient.checkHTTP(response)) { XCTAssertEqual($0 as? LLMError, expected) }
        }
        XCTAssertNoThrow(try LLMClient.checkHTTP(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    }

    /// Separates malformed JSON from empty completions and trims a valid response.
    func testResponseParsing() throws {
        XCTAssertEqual(try LLMClient.parse(Data(#"{"choices":[{"message":{"content":"  answer  "}}]}"#.utf8)), "answer")
        XCTAssertThrowsError(try LLMClient.parse(Data("not json".utf8))) { XCTAssertEqual($0 as? LLMError, .invalidResponse) }
        XCTAssertThrowsError(try LLMClient.parse(Data(#"{"choices":[]}"#.utf8))) { XCTAssertEqual($0 as? LLMError, .emptyResponse) }
    }

    /// Preserves cancellation as cancellation instead of reporting a connection error.
    func testTransportFailureMapping() {
        XCTAssertTrue(LLMClient.map(URLError(.cancelled)) is CancellationError)
        XCTAssertEqual(LLMClient.map(URLError(.timedOut)) as? LLMError, .timeout)
    }

    /// Blocks an unsupported image before the HTTP layer even for direct callers.
    func testImageRejectionBeforeTransport() async {
        let client = LLMClient()
        do {
            _ = try await client.complete(Provider(name: "Text", baseURL: "invalid"), model: "text",
                messages: [ChatMessage(role: "user", content: "", imageURLs: ["data:image/png;base64,YQ=="])], apiKey: nil)
            XCTFail("Expected image rejection")
        } catch { XCTAssertEqual(error as? LLMError, .imagesUnsupported) }
    }
}
