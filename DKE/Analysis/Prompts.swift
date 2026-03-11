import Foundation

enum AnalysisPrompts {
    private static let knowledgeExtractionDefault = """
    You are a domain knowledge extraction specialist. Analyze the following transcript excerpt and extract any implicit domain knowledge.

    For each piece of knowledge found, output a JSON array of objects with these fields:
    - "content": A clear, standalone statement of the knowledge
    - "category": One of: process, heuristic, decision, terminology, relationship, exception, tacit_assumption
    - "source_quote": The exact quote from the transcript
    - "confidence": One of: low, medium, high
    - "tags": Array of relevant topic tags

    If no domain knowledge is found, return an empty array: []
    Output ONLY valid JSON. No explanation.

    Transcript:
    """

    private static let nudgeGenerationDefault = """
    You are an expert interviewer extracting deep domain knowledge in real-time.

    You receive:
    1. RECENT TRANSCRIPT — what is currently being discussed
    2. KNOWLEDGE BASE — what has already been captured

    Your job: Generate 1-2 HIGH-REWARD questions about whatever topic is being discussed RIGHT NOW. High-reward questions unlock knowledge that people don't volunteer on their own.

    Every question MUST use one of these three techniques:

    FORCE A CHOICE — make them pick, rank, or trade off:
    - "If you could only keep X or Y, which matters more?"
    - "What would you sacrifice first if this had half the budget?"
    - "Between speed and accuracy here, which wins?"

    SPECULATE — push into hypotheticals and edge cases:
    - "What would break first if X suddenly doubled in volume?"
    - "If this process disappeared tomorrow, what would happen?"
    - "What's the worst-case scenario you've actually seen with X?"

    MAKE IT PERSONAL — ask for their opinion, experience, gut feel:
    - "What would YOUR ideal outcome for X look like?"
    - "What's the one thing about X that frustrates you most?"
    - "If you redesigned X from scratch, what would you change?"

    Rules:
    - Reference SPECIFIC things from the transcript (names, processes, terms)
    - Never ask yes/no questions
    - Never ask what they already explained
    - Skip topics already well-covered in the Knowledge Base
    - Keep questions short and direct (max 20 words)

    Output ONLY a JSON array of objects with:
    - "question": The high-reward question to ask (short, direct)
    - "type": One of "choice", "speculative", "personal"
    - "reason": What this unlocks (max 8 words)

    If the current topic is well-covered in the KB, return: []
    """

    private static let knowledgeExtractionKey = "com.dke.prompt.knowledgeExtraction"
    private static let nudgeGenerationKey = "com.dke.prompt.nudgeGeneration"

    static var knowledgeExtraction: String {
        get { UserDefaults.standard.string(forKey: knowledgeExtractionKey) ?? knowledgeExtractionDefault }
        set { UserDefaults.standard.set(newValue, forKey: knowledgeExtractionKey) }
    }

    static var nudgeGeneration: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: nudgeGenerationKey) {
                // Migrate: if user still has the old generic prompt, replace with new KB-aware one
                if stored.contains("domain knowledge interviewer assistant") {
                    UserDefaults.standard.removeObject(forKey: nudgeGenerationKey)
                    return nudgeGenerationDefault
                }
                return stored
            }
            return nudgeGenerationDefault
        }
        set { UserDefaults.standard.set(newValue, forKey: nudgeGenerationKey) }
    }

    static func resetKnowledgeExtraction() {
        UserDefaults.standard.removeObject(forKey: knowledgeExtractionKey)
    }

    static func resetNudgeGeneration() {
        UserDefaults.standard.removeObject(forKey: nudgeGenerationKey)
    }
}
