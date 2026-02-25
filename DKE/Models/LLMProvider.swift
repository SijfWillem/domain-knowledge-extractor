import Foundation

// MARK: - Chat Message

/// A single message in a chat conversation.
struct ChatMessage: Sendable {
    enum Role: String, Sendable {
        case system, user, assistant
    }
    let role: Role
    let content: String
}

// MARK: - Completion Request

/// Parameters for an LLM completion request.
struct CompletionRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double

    init(model: String, messages: [ChatMessage], maxTokens: Int = 1024, temperature: Double = 0.7) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

// MARK: - Completion Response

/// The result returned from an LLM completion.
struct CompletionResponse: Sendable {
    let content: String
    let model: String
}

// MARK: - LLM Provider Protocol

/// A unified protocol for all LLM backends (Ollama, OpenAI, Anthropic).
protocol LLMProvider: Sendable {
    /// Human-readable name for this provider.
    var name: String { get }

    /// Perform a non-streaming completion.
    func complete(_ request: CompletionRequest) async throws -> CompletionResponse

    /// Perform a streaming completion, yielding content tokens as they arrive.
    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error>
}
