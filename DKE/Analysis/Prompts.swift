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

    Each question MUST combine ALL THREE of these techniques into a single question:

    1. FORCE A CHOICE — make them pick, rank, or trade off
    2. SPECULATE — push into a hypothetical or edge case
    3. MAKE IT PERSONAL — ask for their opinion, experience, or gut feel

    Examples of questions that combine all three:
    - "If you personally had to choose between X and Y in a crisis, which would you bet on and why?" (choice + speculative + personal)
    - "Imagine X fails tomorrow — what would YOU prioritize rebuilding first, and what would you drop?" (speculative + personal + choice)
    - "If you could redesign X from scratch knowing what you know, what trade-off would you make differently?" (personal + speculative + choice)

    Rules:
    - Every question must force a choice, be speculative, AND be personal — all three in one
    - Reference SPECIFIC things from the transcript (names, processes, terms)
    - Never ask yes/no questions
    - Never ask what they already explained
    - Skip topics already well-covered in the Knowledge Base
    - Keep questions short and direct (max 25 words)

    Output ONLY a JSON array of objects with:
    - "question": The high-reward question (short, direct, combines all 3 techniques)
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
