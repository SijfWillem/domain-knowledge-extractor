import Foundation

// MARK: - Anthropic Provider

/// Direct REST client for the Anthropic Messages API.
/// Handles the Anthropic API's requirement that system messages are passed
/// as a separate parameter rather than inline in the messages array.
final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    let name: String
    private let apiKey: String
    private let baseURL: URL

    init(name: String = "Anthropic", apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - Non-streaming completion

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let (systemPrompt, messages) = separateSystemMessages(request.messages)

        let endpoint = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "messages": messages.map { ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content] }
        ]
        if let system = systemPrompt {
            body["system"] = system
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()

        guard !content.isEmpty else { throw AnthropicProviderError.emptyResponse }

        return CompletionResponse(content: content, model: decoded.model)
    }

    // MARK: - Streaming completion

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (systemPrompt, messages) = self.separateSystemMessages(request.messages)

                    let endpoint = self.baseURL.appendingPathComponent("v1/messages")
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    var body: [String: Any] = [
                        "model": request.model,
                        "max_tokens": request.maxTokens,
                        "temperature": request.temperature,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content] }
                    ]
                    if let system = systemPrompt {
                        body["system"] = system
                    }

                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    try self.validateHTTPResponse(response, data: nil)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]",
                              let lineData = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: lineData),
                              event.type == "content_block_delta",
                              let delta = event.delta,
                              delta.type == "text_delta",
                              let text = delta.text else { continue }
                        continuation.yield(text)
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

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicProviderError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw AnthropicProviderError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

// MARK: - Anthropic API Types

private struct AnthropicResponse: Decodable {
    let model: String
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - Errors

enum AnthropicProviderError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Anthropic returned an empty response."
        case .invalidResponse:
            return "Invalid response from Anthropic."
        case .httpError(let statusCode, let body):
            return "Anthropic HTTP error \(statusCode): \(body)"
        }
    }
}
