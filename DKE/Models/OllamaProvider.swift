import Foundation

// MARK: - Ollama Provider

/// Native Ollama REST API client that communicates with a local Ollama instance
/// via http://localhost:11434/api/chat.
struct OllamaProvider: LLMProvider {
    let name: String
    let baseURL: URL

    init(name: String = "Ollama", host: String = "localhost", port: Int = 11434) {
        self.name = name
        guard let url = URL(string: "http://\(host):\(port)") else {
            fatalError("Invalid Ollama base URL: http://\(host):\(port)")
        }
        self.baseURL = url
    }

    // MARK: - Non-streaming completion

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let endpoint = baseURL.appendingPathComponent("api/chat")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaChatRequest(
            model: request.model,
            messages: request.messages.map { OllamaChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            options: OllamaOptions(temperature: request.temperature, num_predict: request.maxTokens)
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response)

        let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return CompletionResponse(
            content: chatResponse.message.content,
            model: chatResponse.model
        )
    }

    // MARK: - Streaming completion

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = baseURL.appendingPathComponent("api/chat")
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = OllamaChatRequest(
                        model: request.model,
                        messages: request.messages.map {
                            OllamaChatMessage(role: $0.role.rawValue, content: $0.content)
                        },
                        stream: true,
                        options: OllamaOptions(
                            temperature: request.temperature,
                            num_predict: request.maxTokens
                        )
                    )
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    try validateHTTPResponse(response)

                    // Ollama streams newline-delimited JSON objects
                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        guard let lineData = line.data(using: .utf8) else { continue }

                        let chunk = try JSONDecoder().decode(OllamaChatResponse.self, from: lineData)
                        let token = chunk.message.content
                        if !token.isEmpty {
                            continuation.yield(token)
                        }

                        if chunk.done {
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

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Ollama API Types

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaOptions: Encodable {
    let temperature: Double
    let num_predict: Int
}

private struct OllamaChatResponse: Decodable {
    let model: String
    let message: OllamaChatMessage
    let done: Bool
}

// MARK: - Ollama Errors

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama server."
        case .httpError(let statusCode):
            return "Ollama HTTP error: \(statusCode)"
        }
    }
}
