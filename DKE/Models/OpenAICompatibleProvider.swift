import Foundation

// MARK: - OpenAI-Compatible Provider

/// Direct REST client for the OpenAI Chat Completions API.
/// Supports both standard OpenAI (with API key) and custom endpoints
/// (e.g., Ollama in OpenAI-compatible mode, Azure OpenAI, vLLM).
final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    let name: String
    private let baseURL: URL
    private let apiKey: String

    /// Initialize for the standard OpenAI API.
    init(name: String = "OpenAI", apiKey: String) {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = URL(string: "https://api.openai.com")!
    }

    /// Initialize for a custom OpenAI-compatible endpoint.
    init(name: String = "OpenAI Compatible", host: String, port: Int, scheme: String = "http", apiKey: String = "") {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = URL(string: "\(scheme)://\(host):\(port)")!
    }

    // MARK: - Non-streaming completion

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = OpenAIChatRequest(
            model: request.model,
            messages: request.messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) },
            max_tokens: request.maxTokens,
            temperature: request.temperature,
            stream: false
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAICompatibleError.emptyResponse
        }

        return CompletionResponse(content: content, model: decoded.model ?? request.model)
    }

    // MARK: - Streaming completion

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = self.baseURL.appendingPathComponent("v1/chat/completions")
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !self.apiKey.isEmpty {
                        urlRequest.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    let body = OpenAIChatRequest(
                        model: request.model,
                        messages: request.messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) },
                        max_tokens: request.maxTokens,
                        temperature: request.temperature,
                        stream: true
                    )
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    try self.validateHTTPResponse(response, data: nil)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]",
                              let lineData = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: lineData),
                              let delta = chunk.choices.first?.delta.content else { continue }
                        continuation.yield(delta)
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

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw OpenAICompatibleError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

// MARK: - OpenAI API Types

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let max_tokens: Int
    let temperature: Double
    let stream: Bool
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatResponse: Decodable {
    let model: String?
    let choices: [Choice]

    struct Choice: Decodable {
        let message: MessageContent
    }

    struct MessageContent: Decodable {
        let content: String?
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [StreamChoice]

    struct StreamChoice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

// MARK: - Errors

enum OpenAICompatibleError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "OpenAI returned an empty response."
        case .invalidResponse:
            return "Invalid response from OpenAI endpoint."
        case .httpError(let statusCode, let body):
            return "OpenAI HTTP error \(statusCode): \(body)"
        }
    }
}
