import Foundation
import SwiftUI

@MainActor
final class SessionOrchestrator: ObservableObject {
    @Published var isActive = false
    @Published var currentNudges: [NudgeSuggestion] = []
    @Published var transcriptText: String = ""
    @Published var whisperModelLoaded = false

    let audioManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    let analysisEngine: AnalysisEngine
    let router: LLMRouter
    private let dataStore = DataStore()

    private var nudgeTimer: Timer?
    private var analysisTimer: Timer?
    private var currentSession: SessionMO?

    init(router: LLMRouter) {
        self.router = router
        self.analysisEngine = AnalysisEngine(router: router)
    }

    func loadWhisperModel(path: String) async throws {
        try await transcriptionManager.loadModel(path: path)
        whisperModelLoaded = true
    }

    func autoLoadWhisperModel() async {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DKE/models")
        guard let files = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil),
              let modelFile = files.first(where: { $0.pathExtension == "bin" }) else { return }
        try? await loadWhisperModel(path: modelFile.path)
    }

    func startSession(mode: SessionMode) async throws {
        audioManager.mode = mode
        audioManager.chunker.onChunkReady = { [weak self] samples in
            Task { @MainActor in
                guard let self else { return }
                self.transcriptionManager.processChunk(samples)
                self.transcriptText = self.transcriptionManager.latestText
            }
        }
        try await audioManager.startRecording()

        let title = "Session \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        currentSession = dataStore.createSession(title: title, mode: mode)
        try? dataStore.save()

        isActive = true

        nudgeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.generateNudges() }
        }
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.analyzeRecent() }
        }
    }

    func stopSession() async throws {
        nudgeTimer?.invalidate()
        analysisTimer?.invalidate()
        nudgeTimer = nil
        analysisTimer = nil
        try await audioManager.stopRecording()
        isActive = false
        await analyzeRecent()
        persistTranscript()
        persistKnowledge()
        try? dataStore.save()
        currentSession = nil
    }

    private func generateNudges() async {
        let recent = transcriptionManager.transcript.suffix(12).map(\.text).joined(separator: " ")
        guard !recent.isEmpty else { return }
        let modelId = router.modelIdentifier(for: .nudgeGeneration) ?? "llama3.1"
        let summary = analysisEngine.extractedKnowledge.map { "[\($0.category)] \($0.content)" }.joined(separator: "\n")
        await analysisEngine.generateNudges(recentTranscript: recent, knowledgeSummary: summary, modelIdentifier: modelId)
        currentNudges = analysisEngine.currentNudges
    }

    private func analyzeRecent() async {
        let recent = transcriptionManager.transcript.suffix(6).map(\.text).joined(separator: " ")
        guard !recent.isEmpty else { return }
        let modelId = router.modelIdentifier(for: .analysis) ?? "llama3.1"
        await analysisEngine.analyzeTranscript(window: recent, modelIdentifier: modelId)
    }

    private func persistTranscript() {
        guard let session = currentSession else { return }
        for segment in transcriptionManager.transcript {
            dataStore.createTranscriptSegment(
                text: segment.text,
                speaker: segment.speaker,
                startTime: segment.startTime,
                endTime: segment.endTime,
                session: session
            )
        }
    }

    private func persistKnowledge() {
        guard let session = currentSession else { return }
        for atom in analysisEngine.extractedKnowledge {
            let category = KnowledgeCategory(rawValue: atom.category) ?? .technicalExpertise
            let confidence = ConfidenceLevel(rawValue: atom.confidence) ?? .medium
            dataStore.createKnowledgeAtom(
                content: atom.content,
                category: category,
                sourceQuote: atom.source_quote,
                confidence: confidence,
                tags: atom.tags,
                session: session
            )
        }
    }
}
