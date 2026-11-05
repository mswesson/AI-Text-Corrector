import XCTest
@testable import TextCorrectCore

final class RequestBuilderTests: XCTestCase {
    func testInitialTransform() {
        let messages = RequestBuilder.initialTransform(systemPrompt: "sys", text: "hello")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[0].content, "sys")
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, "hello")
    }

    func testRefineUsesDraftNotOriginal() {
        let messages = RequestBuilder.refine(systemPrompt: "sys", currentDraft: "draft text", instruction: "shorter")
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].content.contains("draft text"))
        XCTAssertTrue(messages[1].content.contains("shorter"))
        XCTAssertFalse(messages[1].content.contains("ORIGINAL TEXT"))
    }

    func testChatAppendsHistory() {
        let history = [
            ChatMessage(role: "user", content: "q1"),
            ChatMessage(role: "assistant", content: "a1"),
        ]
        let messages = RequestBuilder.chat(systemPrompt: "sys", history: history, newUserMessage: "q2")
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[1].content, "q1")
        XCTAssertEqual(messages[2].role, "assistant")
        XCTAssertEqual(messages[3].content, "q2")
    }
}
