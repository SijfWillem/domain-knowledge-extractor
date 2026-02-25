import Foundation

enum AnalysisPrompts {
    static let knowledgeExtraction = """
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

    static let nudgeGeneration = """
    You are a domain knowledge interviewer assistant. Based on the recent conversation, suggest 1-2 follow-up questions that would help extract deeper domain knowledge.

    Focus on:
    - Shallow answers that need deeper probing
    - Unexplored branches (edge cases, exceptions mentioned but not explained)
    - Missing rationale (decisions stated without "why")
    - Undefined jargon or domain terms
    - Gaps in described processes

    Output ONLY a JSON array of objects with:
    - "question": The suggested follow-up question
    - "reason": Brief reason why this question matters (max 10 words)

    If no good follow-ups exist, return: []

    Recent transcript (last ~60 seconds):
    """
}
