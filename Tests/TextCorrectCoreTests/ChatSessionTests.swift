import XCTest
@testable import TextCorrectCore

@MainActor
final class ChatSessionTests: XCTestCase {
    /// Keeps unsuccessful request preparation out of successful history.
    func testPreparationDoesNotMutateHistory() {
        let session = ChatSession()
        _ = session.makeMessages(userInput: "question")
        XCTAssertTrue(session.history.isEmpty)
    }

    /// Carries the initial selection forward in subsequent chat requests.
    func testChatPreservesAttachedContextInHistory() {
        let session = ChatSession()
        session.attachedText = "selected code"
        session.applyResponse("explanation", toUserInput: "explain")
        let messages = session.makeMessages(userInput: "more details")
        XCTAssertTrue(messages.contains { $0.role == "user" && $0.content.contains("selected code") })
        XCTAssertNil(session.attachedText)
    }

    /// Uses the manually edited draft for the next transformation.
    func testRefinementUsesEditedDraft() {
        let session = ChatSession(systemPrompt: "fix", mode: .transform)
        session.attachedText = "original"
        session.applyResponse("generated", toUserInput: "")
        session.draft = "manual edit"
        let messages = session.makeMessages(userInput: "shorten")
        XCTAssertTrue(messages.last!.content.contains("manual edit"))
        XCTAssertFalse(messages.last!.content.contains("original"))
        XCTAssertTrue(session.hasManualEdits)
    }

    /// Runs a transformation with only the selected text as input.
    func testTransformNeedsNoAdditionalInstruction() {
        let session = ChatSession(systemPrompt: "translate", mode: .transform)
        session.attachedText = "hello"
        XCTAssertEqual(session.makeMessages(userInput: "").last?.content, "hello")
    }

    /// Clears context, drafts and history on explicit session completion.
    func testClearRemovesSessionContent() {
        let session = ChatSession(mode: .transform)
        session.applyResponse("answer", toUserInput: "question")
        session.clear()
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertNil(session.draft)
        XCTAssertNil(session.attachedText)
        XCTAssertFalse(session.hasManualEdits)
    }
    /// Detects unsaved edits to a chat response without altering its conversation history.
    func testChatManualEditsAreTracked() {
        let session = ChatSession()
        session.applyResponse("answer", toUserInput: "question")
        session.editedResponse = "edited answer"
        XCTAssertTrue(session.hasManualEdits)
        XCTAssertEqual(session.history.last?.content, "answer")
    }

    /// Keeps a successful screenshot in chat context and clears the pending attachment.
    func testImagesRemainInSuccessfulChatHistory() {
        let session = ChatSession()
        session.attachedImages = [Data("image".utf8)]
        let sent = session.makeMessages(userInput: "explain").last!
        XCTAssertEqual(sent.imageURLs, ["data:image/png;base64,aW1hZ2U="])
        session.applyResponse("answer", toUserInput: "explain", sentMessage: sent)
        XCTAssertTrue(session.attachedImages.isEmpty)
        XCTAssertEqual(session.makeMessages(userInput: "details")[1].imageURLs, sent.imageURLs)
        session.clear()
        XCTAssertTrue(session.history.isEmpty)
    }

    /// Attaches screenshots to transform requests without replacing the edited draft.
    func testImagesAccompanyTransformDraft() {
        let session = ChatSession(mode: .transform)
        session.draft = "manual draft"
        session.attachedImages = [Data("image".utf8)]
        let message = session.makeMessages(userInput: "compare with screenshot").last!
        XCTAssertTrue(message.content.contains("manual draft"))
        XCTAssertEqual(message.imageURLs.count, 1)
        session.clear()
        XCTAssertTrue(session.attachedImages.isEmpty)
    }

}
