import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class SessionOrchestrator: ObservableObject {
    @Published var isActive = false
    @Published var currentNudges: [NudgeSuggestion] = []
    @Published var transcriptText: String = ""

    let audioManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    let analysisEngine: AnalysisEngine
    let router: LLMRouter
    private let dataStore = DataStore()

    private var nudgeTimer: Timer?
    private var analysisTimer: Timer?
    private var transcriptSyncTimer: Timer?
    private var currentSession: SessionMO?

    init(router: LLMRouter) {
        self.router = router
        self.analysisEngine = AnalysisEngine(router: router)
        transcriptionManager.requestAuthorization()
    }

    func startSession(mode: SessionMode) async throws {
        audioManager.mode = mode

        // Wire audio buffers to the speech recognizer for real-time transcription
        audioManager.onRawAudioBuffer = { [weak self] buffer in
            Task { @MainActor in
                self?.transcriptionManager.feedAudioBuffer(buffer)
            }
        }

        // Start live speech recognition
        transcriptionManager.startLiveTranscription()

        try await audioManager.startRecording()

        let title = "Session \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        currentSession = dataStore.createSession(title: title, mode: mode)
        try? dataStore.save()

        isActive = true

        // Sync transcript text periodically for the widget
        transcriptSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.transcriptText = self.transcriptionManager.latestText
            }
        }

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
        transcriptSyncTimer?.invalidate()
        nudgeTimer = nil
        analysisTimer = nil
        transcriptSyncTimer = nil

        transcriptionManager.stopLiveTranscription()
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
        let modelId = router.modelIdentifier(for: .nudgeGeneration) ?? "llama3.1:8b"
        let summary = analysisEngine.extractedKnowledge.map { "[\($0.category)] \($0.content)" }.joined(separator: "\n")
        await analysisEngine.generateNudges(recentTranscript: recent, knowledgeSummary: summary, modelIdentifier: modelId)
        currentNudges = analysisEngine.currentNudges
    }

    private func analyzeRecent() async {
        let recent = transcriptionManager.transcript.suffix(6).map(\.text).joined(separator: " ")
        guard !recent.isEmpty else { return }
        let modelId = router.modelIdentifier(for: .analysis) ?? "llama3.1:8b"
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
            let category: KnowledgeCategory = KnowledgeCategory(rawValue: atom.category) ?? .process
            let confidence: ConfidenceLevel = ConfidenceLevel(rawValue: atom.confidence) ?? .medium
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
