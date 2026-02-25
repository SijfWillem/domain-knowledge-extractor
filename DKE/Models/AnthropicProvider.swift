import Foundation
import Anthropic

// MARK: - Anthropic Provider

/// An LLM provider that uses the anthropic-sdk-swift package.
/// Handles the Anthropic API's requirement that system messages are passed
/// as a separate parameter rather than inline in the messages array.
final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    let name: String
    private let client: Client

    /// Initialize with an Anthropic API key.
    /// - Parameters:
    ///   - name: Human-readable provider name.
    ///   - apiKey: Your Anthropic API key.
    init(name: String = "Anthropic", apiKey: String) {
        self.name = name
        self.client = Client(apiKey: apiKey)
    }

    // MARK: - Non-streaming completion

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let (systemPrompt, messages) = separateSystemMessages(request.messages)

        let anthropicMessages = messages.map { message -> Message.Parameter in
            Message.Parameter(
                role: message.role == .assistant ? .assistant : .user,
                content: .text(message.content)
            )
        }

        let response = try await client.messages.create(
            model: Model(request.model),
            maxTokens: request.maxTokens,
            system: systemPrompt.map { .text($0) },
            messages: anthropicMessages,
            temperature: request.temperature
        )

        let content = response.content
            .compactMap { block -> String? in
                if case .text(let text) = block {
                    return text
                }
                return nil
            }
            .joined()

        guard !content.isEmpty else {
            throw AnthropicProviderError.emptyResponse
        }

        return CompletionResponse(
            content: content,
            model: request.model
        )
    }

    // MARK: - Streaming completion

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (systemPrompt, messages) = separateSystemMessages(request.messages)

                    let anthropicMessages = messages.map { message -> Message.Parameter in
                        Message.Parameter(
                            role: message.role == .assistant ? .assistant : .user,
                            content: .text(message.content)
                        )
                    }

                    let stream = try client.messages.stream(
                        model: Model(request.model),
                        maxTokens: request.maxTokens,
                        system: systemPrompt.map { .text($0) },
                        messages: anthropicMessages,
                        temperature: request.temperature
                    )

                    for try await event in stream {
                        switch event {
                        case .contentBlockDelta(let delta):
                            if case .textDelta(let text) = delta.delta {
                                continuation.yield(text)
                            }
                        case .messageStop:
                            break
                        default:
                            break
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

    // MARK: - Helpers

    /// Separates system messages from the conversation and returns them as a single
    /// system prompt string plus the remaining non-system messages.
    /// The Anthropic API requires system messages as a separate parameter.
    private func separateSystemMessages(_ messages: [ChatMessage]) -> (String?, [ChatMessage]) {
        var systemParts: [String] = []
        var conversationMessages: [ChatMessage] = []

        for message in messages {
            if message.role == .system {
                systemParts.append(message.content)
            } else {
                conversationMessages.append(message)
            }
        }

        let systemPrompt = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (systemPrompt, conversationMessages)
    }
}

// MARK: - Errors

enum AnthropicProviderError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Anthropic returned an empty response."
        }
    }
}
