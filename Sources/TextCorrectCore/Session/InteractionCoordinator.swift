import Foundation
import Observation

/// Runs LLM requests for a session: one active request, cancellation, late-response protection.
@MainActor
@Observable
public final class InteractionCoordinator {
    public enum Phase: Equatable {
        case idle
        case generating
        case error(String)
    }

    public private(set) var phase: Phase = .idle
    private var generationID = 0
    private let client: any LLMCompleting
    private var request: Task<String, Error>?

    public init(client: any LLMCompleting = LLMClient()) {
        self.client = client
    }

    public var isBusy: Bool { phase == .generating }

    /// Sends a request. Returns the response text, or nil if cancelled/superseded.
    public func send(
        session: ChatSession,
        userInput: String,
        provider: Provider,
        model: String,
        apiKey: String?
    ) async -> String? {
        guard !isBusy else { return nil }
        generationID += 1
        let id = generationID
        phase = .generating
        defer {
            if generationID == id {
                request = nil
                if phase == .generating { phase = .idle }
            }
        }

        let messages = session.makeMessages(userInput: userInput)
        guard provider.supportsImages(model: model) || !messages.contains(where: { !$0.imageURLs.isEmpty }) else {
            phase = .error(LLMError.imagesUnsupported.message)
            return nil
        }
        let client = client
        let task = Task {
            try await client.complete(provider, model: model, messages: messages, apiKey: apiKey)
        }
        request = task
        do {
            let text = try await task.value
            guard generationID == id else { return nil }   // superseded/cancelled
            session.applyResponse(text, toUserInput: userInput, sentMessage: messages.last)
            return text
        } catch is CancellationError {
            return nil
        } catch {
            guard generationID == id else { return nil }
            phase = .error((error as? LLMError)?.message ?? error.localizedDescription)
            return nil
        }
    }

    /// Cancels the transport and rejects responses from the cancelled generation.
    public func cancel() {
        request?.cancel()
        request = nil
        generationID += 1
        if case .generating = phase { phase = .idle }
    }
}
