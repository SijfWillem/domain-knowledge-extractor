import Foundation

// MARK: - LLM Router

/// A provider registry that maps DKE pipeline tasks to specific LLM providers.
/// Each task (transcription, analysis, nudge generation) can be assigned to a
/// different provider, enabling flexible model routing.
@MainActor
final class LLMRouter: ObservableObject {
    @Published var providers: [String: any LLMProvider] = [:]
    @Published var taskAssignments: [DKETask: String] = [:]
    @Published var modelIdentifiers: [String: String] = [:]

    init() {
        // Default: register local Ollama with llama3.2:3b for all tasks
        let ollama = OllamaProvider()
        providers["ollama"] = ollama
        modelIdentifiers["ollama"] = "llama3.2:3b"
        taskAssignments[.analysis] = "ollama"
        taskAssignments[.nudgeGeneration] = "ollama"
    }

    /// Register an LLM provider under a given key.
    func register(_ provider: any LLMProvider, as key: String) {
        providers[key] = provider
    }

    /// Store the model identifier for a registered provider key.
    func setModelIdentifier(_ identifier: String, for providerKey: String) {
        modelIdentifiers[providerKey] = identifier
    }

    /// Look up the provider assigned to a specific DKE task.
    func provider(for task: DKETask) -> (any LLMProvider)? {
        guard let key = taskAssignments[task] else { return nil }
        return providers[key]
    }

    /// Look up the model identifier for a specific DKE task.
    func modelIdentifier(for task: DKETask) -> String? {
        guard let key = taskAssignments[task] else { return nil }
        return modelIdentifiers[key]
    }

    /// Assign a DKE task to a registered provider key.
    func assign(task: DKETask, to providerKey: String) {
        taskAssignments[task] = providerKey
    }
}
