import SwiftUI

struct SettingsView: View {
    @ObservedObject var router: LLMRouter
    @ObservedObject var orchestrator: SessionOrchestrator
    @State private var newModelName = ""
    @State private var newModelEndpoint = "http://localhost:11434"
    @State private var newModelType: ModelType = .ollama
    @State private var newModelIdentifier = ""
    @State private var newApiKey = ""
    @State private var selectedLanguage = DKELanguage.current
    @State private var knowledgePrompt = AnalysisPrompts.knowledgeExtraction
    @State private var nudgePrompt = AnalysisPrompts.nudgeGeneration

    var body: some View {
        ScrollView {
        Form {
            Section("Registered Models") {
                if router.providers.isEmpty {
                    Text("No models registered. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(router.providers.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key).font(.headline)
                        Spacer()
                        if let modelId = router.modelIdentifiers[key] {
                            Text(modelId).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Add Model") {
                TextField("Display Name", text: $newModelName)
                Picker("Provider", selection: $newModelType) {
                    Text("Ollama").tag(ModelType.ollama)
                    Text("OpenAI Compatible").tag(ModelType.openAICompatible)
                    Text("Anthropic").tag(ModelType.anthropic)
                }
                TextField("Model ID (e.g. llama3.1:8b)", text: $newModelIdentifier)
                if newModelType == .anthropic || newModelType == .openAICompatible {
                    SecureField("API Key", text: $newApiKey)
                }
                Button("Add Model") { addModel() }
                    .disabled(newModelName.isEmpty || newModelIdentifier.isEmpty)
            }

            Section("Task Assignment") {
                ForEach(DKETask.allCases, id: \.self) { task in
                    Picker(task.rawValue, selection: taskBinding(for: task)) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(Array(router.providers.keys.sorted()), id: \.self) { key in
                            Text(key).tag(Optional(key))
                        }
                    }
                }
            }

            Section("Language") {
                Picker("Speech Language", selection: $selectedLanguage) {
                    ForEach(DKELanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    DKELanguage.current = newValue
                    orchestrator.transcriptionManager.setLanguage(newValue)
                }
                Text("Sets the language for speech recognition and LLM analysis. Change before starting a session.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription") {
                HStack {
                    Circle()
                        .fill(orchestrator.transcriptionManager.micTranscriber.isAuthorized ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(orchestrator.transcriptionManager.micTranscriber.isAuthorized
                         ? "Speech recognition authorized"
                         : "Speech recognition not authorized")
                        .font(.caption)
                }
                Text("Uses Apple's built-in Speech framework for on-device transcription.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Knowledge Extraction Prompt") {
                TextEditor(text: $knowledgePrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .onChange(of: knowledgePrompt) { _, newValue in
                        AnalysisPrompts.knowledgeExtraction = newValue
                    }
                Button("Reset to Default") {
                    AnalysisPrompts.resetKnowledgeExtraction()
                    knowledgePrompt = AnalysisPrompts.knowledgeExtraction
                }
                .font(.caption)
            }

            Section("Nudge Generation Prompt") {
                TextEditor(text: $nudgePrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .onChange(of: nudgePrompt) { _, newValue in
                        AnalysisPrompts.nudgeGeneration = newValue
                    }
                Button("Reset to Default") {
                    AnalysisPrompts.resetNudgeGeneration()
                    nudgePrompt = AnalysisPrompts.nudgeGeneration
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        }
        .frame(width: 500)
        .padding()
    }

    private func addModel() {
        let provider: any LLMProvider
        switch newModelType {
        case .ollama:
            provider = OllamaProvider(name: newModelName)
        case .openAICompatible:
            if newApiKey.isEmpty {
                provider = OpenAICompatibleProvider(name: newModelName, host: "localhost", port: 11434)
            } else {
                provider = OpenAICompatibleProvider(apiKey: newApiKey)
            }
        case .anthropic:
            provider = AnthropicProvider(apiKey: newApiKey)
        case .whisperLocal:
            return
        }
        router.register(provider, as: newModelName)
        router.setModelIdentifier(newModelIdentifier, for: newModelName)
        newModelName = ""
        newModelIdentifier = ""
        newApiKey = ""
    }

    private func taskBinding(for task: DKETask) -> Binding<String?> {
        Binding(
            get: { router.taskAssignments[task] },
            set: {
                if let key = $0 {
                    router.assign(task: task, to: key)
                } else {
                    router.taskAssignments[task] = nil
                }
            }
        )
    }
}
