import XCTest
@testable import TextCorrectCore

private actor ControlledClient: LLMCompleting {
    private var response: CheckedContinuation<String, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    private(set) var wasCancelled = false

    /// Suspends the transport until the test supplies a response.
    func complete(_ provider: Provider, model: String, messages: [ChatMessage], apiKey: String?) async throws -> String {
        callCount += 1
        let text = try await withCheckedThrowingContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
        wasCancelled = Task.isCancelled
        return text
    }

    /// Waits for request preparation without relying on timing delays.
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    /// Resolves the currently suspended transport.
    func finish(_ result: Result<String, Error>) {
        response?.resume(with: result)
        response = nil
    }
}

@MainActor
final class InteractionCoordinatorTests: XCTestCase {
    private let provider = Provider(name: "Test", baseURL: "http://localhost:1234/v1")

    /// Preserves the error phase, draft and successful history after a failed request.
    func testFailurePreservesState() async {
        let client = ControlledClient()
        let coordinator = InteractionCoordinator(client: client)
        let session = ChatSession(mode: .transform)
        session.applyResponse("draft", toUserInput: "original")
        let history = session.history
        let request = Task { await coordinator.send(session: session, userInput: "shorter", provider: provider, model: "test", apiKey: nil) }
        await client.waitUntilStarted()
        await client.finish(.failure(LLMError.timeout))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertEqual(coordinator.phase, .error(LLMError.timeout.message))
        XCTAssertEqual(session.draft, "draft")
        XCTAssertEqual(session.history, history)
    }

    /// Cancels the transport, prevents duplicate requests and rejects a late response.
    func testCancellationRejectsLateResponse() async {
        let client = ControlledClient()
        let coordinator = InteractionCoordinator(client: client)
        let session = ChatSession()
        let request = Task { await coordinator.send(session: session, userInput: "question", provider: provider, model: "test", apiKey: nil) }
        await client.waitUntilStarted()
        let duplicate = await coordinator.send(session: session, userInput: "duplicate", provider: provider, model: "test", apiKey: nil)
        XCTAssertNil(duplicate)
        coordinator.cancel()
        await client.finish(.success("late answer"))
        let result = await request.value
        let cancelled = await client.wasCancelled
        XCTAssertNil(result)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(coordinator.phase, .idle)
    }
    /// Rejects image requests before transport and retains the screenshot for another model.
    func testUnsupportedModelKeepsAttachmentAndDoesNotSend() async {
        let client = ControlledClient()
        let coordinator = InteractionCoordinator(client: client)
        let session = ChatSession()
        let image = Data("image".utf8)
        session.attachedImages = [image]
        let result = await coordinator.send(session: session, userInput: "explain", provider: provider, model: "text", apiKey: nil)
        let calls = await client.callCount
        XCTAssertNil(result)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(session.attachedImages, [image])
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(coordinator.phase, .error(LLMError.imagesUnsupported.message))
    }

    /// Retains pending images when a supported request fails or is cancelled.
    func testImageFailureAndCancellationPreserveAttachment() async {
        let client = ControlledClient()
        let coordinator = InteractionCoordinator(client: client)
        let session = ChatSession()
        session.attachedImages = [Data("image".utf8)]
        var vision = provider
        vision.visionModelIDs = ["vision"]
        let request = Task { await coordinator.send(session: session, userInput: "explain", provider: vision, model: "vision", apiKey: nil) }
        await client.waitUntilStarted()
        await client.finish(.failure(LLMError.timeout))
        _ = await request.value
        XCTAssertEqual(session.attachedImages.count, 1)
        let retry = Task { await coordinator.send(session: session, userInput: "explain", provider: vision, model: "vision", apiKey: nil) }
        await client.waitUntilStarted()
        coordinator.cancel()
        await client.finish(.success("late answer"))
        _ = await retry.value
        XCTAssertEqual(session.attachedImages.count, 1)
        XCTAssertTrue(session.history.isEmpty)
    }

    /// Blocks an incompatible model when images are already present in chat history.
    func testTextModelCannotReceiveImageHistory() async {
        let client = ControlledClient()
        let coordinator = InteractionCoordinator(client: client)
        let session = ChatSession()
        session.attachedImages = [Data("image".utf8)]
        session.applyResponse("answer", toUserInput: "explain")
        let history = session.history
        _ = await coordinator.send(session: session, userInput: "details", provider: provider, model: "text", apiKey: nil)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(session.history, history)
        XCTAssertEqual(coordinator.phase, .error(LLMError.imagesUnsupported.message))
    }

}
