import Foundation
import OpenAI

// MARK: - OpenAI-Compatible Provider

/// An LLM provider that uses the MacPaw/OpenAI Swift package.
/// Supports both standard OpenAI (with API key) and custom endpoints
/// (e.g., Ollama in OpenAI-compatible mode).
final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    let name: String
    private let client: OpenAI

    /// Initialize for the standard OpenAI API.
    /// - Parameters:
    ///   - name: Human-readable provider name.
    ///   - apiKey: Your OpenAI API key.
    init(name: String = "OpenAI", apiKey: String) {
        self.name = name
        let configuration = OpenAI.Configuration(token: apiKey)
        self.client = OpenAI(configuration: configuration)
    }

    /// Initialize for a custom OpenAI-compatible endpoint (e.g., Ollama).
    /// - Parameters:
    ///   - name: Human-readable provider name.
    ///   - host: The hostname of the endpoint.
    ///   - port: The port number.
    ///   - scheme: The URL scheme (http or https).
    ///   - apiKey: Optional API key (empty string if not required).
    init(name: String = "OpenAI Compatible", host: String, port: Int, scheme: String = "http", apiKey: String = "") {
        self.name = name
        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: port,
            scheme: scheme
        )
        self.client = OpenAI(configuration: configuration)
    }

    // MARK: - Non-streaming completion

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let chatMessages = request.messages.map { message -> ChatQuery.ChatCompletionMessageParam in
            switch message.role {
            case .system:
                return .init(role: .system, content: message.content)!
            case .user:
                return .init(role: .user, content: message.content)!
            case .assistant:
                return .init(role: .assistant, content: message.content)!
            }
        }

        let query = ChatQuery(
            messages: chatMessages,
            model: .init(request.model),
            maxTokens: request.maxTokens,
            temperature: request.temperature
        )

        let result = try await client.chats(query: query)

        guard let content = result.choices.first?.message.content?.string else {
            throw OpenAICompatibleError.emptyResponse
        }

        return CompletionResponse(
            content: content,
            model: result.model ?? request.model
        )
    }

    // MARK: - Streaming completion

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let chatMessages = request.messages.map { message -> ChatQuery.ChatCompletionMessageParam in
                        switch message.role {
                        case .system:
                            return .init(role: .system, content: message.content)!
                        case .user:
                            return .init(role: .user, content: message.content)!
                        case .assistant:
                            return .init(role: .assistant, content: message.content)!
                        }
                    }

                    let query = ChatQuery(
                        messages: chatMessages,
                        model: .init(request.model),
                        maxTokens: request.maxTokens,
                        temperature: request.temperature
                    )

                    let stream = client.chatsStream(query: query)
                    for try await result in stream {
                        if let delta = result.choices.first?.delta.content {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Errors

enum OpenAICompatibleError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "OpenAI returned an empty response."
        }
    }
}
