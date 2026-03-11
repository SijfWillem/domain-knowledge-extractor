import Foundation

private func dkeLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let path = "/tmp/dke-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

struct ExtractedKnowledge: Codable {
    let content: String
    let category: String
    let source_quote: String
    let confidence: String
    let tags: [String]
}

struct NudgeSuggestion: Codable {
    let question: String
    let type: String?
    let reason: String?

    // Accept any extra keys the model might add without failing
    struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        self.question = try container.decode(String.self, forKey: AnyCodingKey(stringValue: "question")!)
        self.type = try? container.decode(String.self, forKey: AnyCodingKey(stringValue: "type")!)
        self.reason = try? container.decode(String.self, forKey: AnyCodingKey(stringValue: "reason")!)
    }
}

@MainActor
final class AnalysisEngine: ObservableObject {
    @Published var extractedKnowledge: [ExtractedKnowledge] = []
    @Published var currentNudges: [NudgeSuggestion] = []

    private let router: LLMRouter

    init(router: LLMRouter) {
        self.router = router
    }

    private func languageSuffix() -> String {
        let lang = DKELanguage.current
        if lang == .english { return "" }
        return "\n\nIMPORTANT: The transcript is in \(lang.llmInstruction). Write the \"content\" and \"source_quote\" fields in \(lang.llmInstruction). Keep JSON keys and category/confidence values in English."
    }

    private func nudgeLanguageSuffix() -> String {
        let lang = DKELanguage.current
        if lang == .english { return "" }
        return "\n\nIMPORTANT: The transcript is in \(lang.llmInstruction). Write the \"question\" field in \(lang.llmInstruction) so the interviewer can ask it directly. Keep the \"reason\" field in English."
    }

    func analyzeTranscript(window: String, modelIdentifier: String) async {
        guard let provider = router.provider(for: .analysis) else {
            dkeLog("ANALYSIS: No provider for .analysis role")
            return
        }
        dkeLog("ANALYSIS: Analyzing transcript window (\(window.count) chars) with model '\(modelIdentifier)'")
        let systemPrompt = AnalysisPrompts.knowledgeExtraction + languageSuffix()
        let request = CompletionRequest(
            model: modelIdentifier,
            messages: [
                ChatMessage(role: .system, content: systemPrompt),
                ChatMessage(role: .user, content: window)
            ],
            maxTokens: 2048,
            temperature: 0.3
        )
        do {
            let response = try await provider.complete(request)
            dkeLog("ANALYSIS: Got response (\(response.content.count) chars): '\(response.content.prefix(200))'")
            let cleaned = Self.extractJSON(from: response.content)
            if let data = cleaned.data(using: .utf8),
               let atoms = try? JSONDecoder().decode([ExtractedKnowledge].self, from: data) {
                extractedKnowledge.append(contentsOf: atoms)
                dkeLog("ANALYSIS: Extracted \(atoms.count) knowledge atoms")
            } else {
                dkeLog("ANALYSIS: Failed to decode JSON from response")
            }
        } catch {
            dkeLog("ANALYSIS: Error: \(error)")
        }
    }

    func generateNudges(recentTranscript: String, knowledgeSummary: String, modelIdentifier: String) async {
        guard let provider = router.provider(for: .nudgeGeneration) else {
            dkeLog("NUDGE: No provider for .nudgeGeneration role")
            return
        }
        let kbSection = knowledgeSummary.isEmpty ? "(empty — nothing captured yet)" : knowledgeSummary
        let context = """
        === RECENT TRANSCRIPT ===
        \(recentTranscript)

        === KNOWLEDGE BASE (already captured) ===
        \(kbSection)
        """
        dkeLog("NUDGE: Generating nudges with model '\(modelIdentifier)', context=\(context.count) chars")
        let systemPrompt = AnalysisPrompts.nudgeGeneration + nudgeLanguageSuffix()
        let request = CompletionRequest(
            model: modelIdentifier,
            messages: [
                ChatMessage(role: .system, content: systemPrompt),
                ChatMessage(role: .user, content: context)
            ],
            maxTokens: 512,
            temperature: 0.5
        )
        do {
            let response = try await provider.complete(request)
            dkeLog("NUDGE: Got response (\(response.content.count) chars): '\(response.content.prefix(200))'")
            let cleaned = Self.extractJSON(from: response.content)
            if let data = cleaned.data(using: .utf8) {
                do {
                    let nudges = try JSONDecoder().decode([NudgeSuggestion].self, from: data)
                    currentNudges = nudges
                    dkeLog("NUDGE: Generated \(nudges.count) nudges")
                } catch {
                    dkeLog("NUDGE: Decode error: \(error)")
                    dkeLog("NUDGE: Cleaned JSON: \(cleaned.prefix(500))")
                }
            } else {
                dkeLog("NUDGE: Could not convert to data")
            }
        } catch {
            dkeLog("NUDGE: Error: \(error)")
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
