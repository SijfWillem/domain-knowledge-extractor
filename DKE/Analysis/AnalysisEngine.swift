import Foundation

struct ExtractedKnowledge: Codable {
    let content: String
    let category: String
    let source_quote: String
    let confidence: String
    let tags: [String]
}

struct NudgeSuggestion: Codable {
    let question: String
    let reason: String
}

@MainActor
final class AnalysisEngine: ObservableObject {
    @Published var extractedKnowledge: [ExtractedKnowledge] = []
    @Published var currentNudges: [NudgeSuggestion] = []

    private let router: LLMRouter

    init(router: LLMRouter) {
        self.router = router
    }

    func analyzeTranscript(window: String, modelIdentifier: String) async {
        guard let provider = router.provider(for: .analysis) else { return }
        let request = CompletionRequest(
            model: modelIdentifier,
            messages: [
                ChatMessage(role: .system, content: AnalysisPrompts.knowledgeExtraction),
                ChatMessage(role: .user, content: window)
            ],
            maxTokens: 2048,
            temperature: 0.3
        )
        do {
            let response = try await provider.complete(request)
            let cleaned = Self.extractJSON(from: response.content)
            if let data = cleaned.data(using: .utf8),
               let atoms = try? JSONDecoder().decode([ExtractedKnowledge].self, from: data) {
                extractedKnowledge.append(contentsOf: atoms)
            }
        } catch {
            print("Analysis error: \(error)")
        }
    }

    func generateNudges(recentTranscript: String, knowledgeSummary: String, modelIdentifier: String) async {
        guard let provider = router.provider(for: .nudgeGeneration) else { return }
        let context = "\(recentTranscript)\n\nKnowledge extracted so far:\n\(knowledgeSummary)"
        let request = CompletionRequest(
            model: modelIdentifier,
            messages: [
                ChatMessage(role: .system, content: AnalysisPrompts.nudgeGeneration),
                ChatMessage(role: .user, content: context)
            ],
            maxTokens: 512,
            temperature: 0.5
        )
        do {
            let response = try await provider.complete(request)
            let cleaned = Self.extractJSON(from: response.content)
            if let data = cleaned.data(using: .utf8),
               let nudges = try? JSONDecoder().decode([NudgeSuggestion].self, from: data) {
                currentNudges = nudges
            }
        } catch {
            print("Nudge generation error: \(error)")
        }
    }

    /// Strip markdown code fences that LLMs commonly wrap around JSON output.
    private static func extractJSON(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
