import Foundation
import Observation

/// In-memory AI session: dialog history + attached context. Never persisted.
@MainActor
@Observable
public final class ChatSession {
    public enum Mode { case chat, transform }

    public private(set) var history: [ChatMessage] = []
    public private(set) var systemPrompt: String
    public private(set) var mode: Mode
    /// Working draft for transform mode; nil in chat mode.
    public var draft: String?
    /// Attached context (selected text, images) for the next request.
    public var attachedText: String?
    public var editedResponse: String?
    public var hasManualEdits: Bool {
        guard let edited = mode == .transform ? draft : editedResponse else { return false }
        return edited != history.last(where: { $0.role == "assistant" })?.content
    }
    public var attachedImages: [Data] = []

    public init(systemPrompt: String = "", mode: Mode = .chat) {
        self.systemPrompt = systemPrompt
        self.mode = mode
    }

    /// Selects the prompt and interaction mode.
    public func configure(systemPrompt: String, mode: Mode) {
        self.systemPrompt = systemPrompt
        self.mode = mode
    }

    /// Builds a request without changing successful session history.
    public func makeMessages(userInput: String) -> [ChatMessage] {
        var messages: [ChatMessage]
        switch mode {
        case .chat:
            let context = attachedText.map { "\($0)\n\n---\n\n\(userInput)" } ?? userInput
            messages = RequestBuilder.chat(systemPrompt: systemPrompt, history: history, newUserMessage: context)
        case .transform:
            if let draft {
                messages = RequestBuilder.refine(systemPrompt: systemPrompt, currentDraft: draft, instruction: userInput)
            } else if let attachedText {
                messages = RequestBuilder.initialTransform(systemPrompt: systemPrompt, text: attachedText)
            } else {
                messages = RequestBuilder.chat(systemPrompt: systemPrompt, history: history, newUserMessage: userInput)
            }
        }
        messages[messages.count - 1].imageURLs = attachedImages.map {
            "data:image/png;base64," + $0.base64EncodedString()
        }
        return messages
    }

    /// Applies a successful LLM response.
    public func applyResponse(_ text: String, toUserInput: String, sentMessage: ChatMessage? = nil) {
        history.append(sentMessage ?? makeMessages(userInput: toUserInput).last ?? ChatMessage(role: "user", content: toUserInput))
        history.append(ChatMessage(role: "assistant", content: text))
        if mode == .transform {
            draft = text
        }
        editedResponse = text
        attachedText = nil
        attachedImages = []
    }

    /// Removes all transient conversation content.
    public func clear() {
        history = []
        draft = nil
        editedResponse = nil
        attachedText = nil
        attachedImages = []
    }
}
