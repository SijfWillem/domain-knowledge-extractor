import Foundation

// MARK: - Session Mode

/// The mode in which a knowledge-extraction session takes place.
enum SessionMode: String, CaseIterable, Codable {
    case inPerson = "in_person"
    case virtual = "virtual"
}

// MARK: - Knowledge Category

/// Classification categories for extracted knowledge atoms.
enum KnowledgeCategory: String, CaseIterable, Codable {
    case process
    case heuristic
    case decision
    case terminology
    case relationship
    case exception
    case tacitAssumption = "tacit_assumption"
}

// MARK: - Confidence Level

/// Confidence level assigned to an extracted knowledge atom.
enum ConfidenceLevel: String, CaseIterable, Codable {
    case low
    case medium
    case high
}

// MARK: - Language

/// Supported speech recognition and analysis languages.
enum DKELanguage: String, CaseIterable {
    case english = "en-US"
    case dutch = "nl-NL"

    var displayName: String {
        switch self {
        case .english: "English"
        case .dutch: "Nederlands (Dutch)"
        }
    }

    var localeIdentifier: String { rawValue }

    /// The language name used in LLM prompt instructions.
    var llmInstruction: String {
        switch self {
        case .english: "English"
        case .dutch: "Dutch"
        }
    }

    private static let key = "com.dke.language"

    static var current: DKELanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let lang = DKELanguage(rawValue: raw) {
                return lang
            }
            return .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

// MARK: - Model Type

/// The type of AI model backend used for inference.
enum ModelType: String, CaseIterable, Codable {
    case ollama
    case openAICompatible = "openai_compatible"
    case anthropic
    case whisperLocal = "whisper_local"
}

// MARK: - DKE Task

/// Tasks that an AI model can be assigned to within the DKE pipeline.
enum DKETask: String, CaseIterable, Codable {
    case transcription
    case analysis
    case nudgeGeneration = "nudge_generation"
}
