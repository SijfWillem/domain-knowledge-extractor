import SwiftUI

struct SettingsView: View {
    @ObservedObject var router: LLMRouter
    @ObservedObject var orchestrator: SessionOrchestrator
    @State private var newModelName = ""
    @State private var newModelEndpoint = "http://localhost:11434"
    @State private var newModelType: ModelType = .ollama
    @State private var newModelIdentifier = ""
    @State private var newApiKey = ""
    @State private var whisperLoadError: String?

    var body: some View {
        Form {
            Section("Registered Models") {
                ForEach(Array(router.providers.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key).font(.headline)
                        Spacer()
                        Text(router.providers[key]?.name ?? "").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Add Model") {
                TextField("Name", text: $newModelName)
                Picker("Provider", selection: $newModelType) {
                    Text("Ollama").tag(ModelType.ollama)
                    Text("OpenAI Compatible").tag(ModelType.openAICompatible)
                    Text("Anthropic").tag(ModelType.anthropic)
                }
                TextField("Endpoint", text: $newModelEndpoint)
                TextField("Model ID (e.g. llama3.1)", text: $newModelIdentifier)
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

            Section("Whisper Model") {
                HStack {
                    Circle()
                        .fill(orchestrator.whisperModelLoaded ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(orchestrator.whisperModelLoaded ? "Model loaded" : "No model loaded")
                        .font(.caption)
                }
                Button("Load Whisper Model...") { pickWhisperModel() }
                if let error = whisperLoadError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Place .bin model files in ~/Library/Application Support/DKE/models/ for auto-loading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

    private func pickWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.message = "Select a Whisper .bin model file"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    whisperLoadError = nil
                    try await orchestrator.loadWhisperModel(path: url.path)
                } catch {
                    whisperLoadError = error.localizedDescription
                }
            }
        }
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
