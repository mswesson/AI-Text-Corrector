import Foundation

public enum RequestBuilder {
    /// First transform request: system prompt + the selected text.
    public static func initialTransform(systemPrompt: String, text: String) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text),
        ]
    }

    /// Follow-up instruction applied to the current draft — never the original text.
    public static func refine(systemPrompt: String, currentDraft: String, instruction: String) -> [ChatMessage] {
        let user = """
        Ниже — текущий текст и отдельная инструкция. Отредактируй текст строго по инструкции.

        <text>
        \(currentDraft)
        </text>

        <instruction>
        \(instruction)
        </instruction>
        """
        return [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: user),
        ]
    }

    /// Chat-mode request that carries the in-memory dialog history.
    public static func chat(systemPrompt: String, history: [ChatMessage], newUserMessage: String) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: history)
        messages.append(ChatMessage(role: "user", content: newUserMessage))
        return messages
    }
}
