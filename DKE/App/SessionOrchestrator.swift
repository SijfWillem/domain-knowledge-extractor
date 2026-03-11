import Foundation
import SwiftUI
import AVFoundation

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

@MainActor
final class SessionOrchestrator: ObservableObject {
    @Published var isActive = false
    @Published var currentNudges: [NudgeSuggestion] = []
    @Published var transcriptText: String = ""
    @Published var isSystemAudioActive = false

    let audioManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    let analysisEngine: AnalysisEngine
    let router: LLMRouter
    private let dataStore = DataStore()

    private var analysisTimer: Timer?
    private var transcriptSyncTimer: Timer?
    private var currentSession: SessionMO?

    private var rawBufferCount = 0
    private var sysBufferCount = 0

    /// Nudge generation
    private var nudgeTimer: Timer?
    private var isGeneratingNudge = false
    /// Minimum time nudges stay visible before being replaced
    private var nudgesShownAt: Date = .distantPast

    init(router: LLMRouter) {
        self.router = router
        self.analysisEngine = AnalysisEngine(router: router)
        dkeLog("ORCH: Init — requesting speech authorization")
        transcriptionManager.requestAuthorization()
    }

    func startSession(mode: SessionMode) async throws {
        dkeLog("ORCH: startSession mode=\(mode)")
        audioManager.mode = mode
        rawBufferCount = 0
        sysBufferCount = 0

        // Wire mic audio → mic speech transcriber (audio thread, synchronous)
        let micTranscriber = transcriptionManager.micTranscriber
        audioManager.onRawAudioBuffer = { [weak self] buffer in
            micTranscriber.appendAudioBuffer(buffer)
            guard let self else { return }
            self.rawBufferCount += 1
            if self.rawBufferCount == 1 || self.rawBufferCount % 200 == 0 {
                dkeLog("ORCH: micBuffer #\(self.rawBufferCount)")
            }
        }

        // Wire system audio → system speech transcriber (ScreenCaptureKit thread, synchronous)
        let sysTranscriber = transcriptionManager.systemTranscriber
        audioManager.onSystemAudioBuffer = { [weak self] buffer in
            sysTranscriber.appendAudioBuffer(buffer)
            guard let self else { return }
            self.sysBufferCount += 1
            if self.sysBufferCount == 1 || self.sysBufferCount % 200 == 0 {
                dkeLog("ORCH: sysBuffer #\(self.sysBufferCount), frames=\(buffer.frameLength)")
            }
        }

        // Start live speech recognition (system audio only if virtual mode)
        let includeSystemAudio = (mode == .virtual)
        dkeLog("ORCH: Starting live transcription, includeSystemAudio=\(includeSystemAudio)")
        transcriptionManager.startLiveTranscription(includeSystemAudio: includeSystemAudio)

        dkeLog("ORCH: Starting audio recording")
        try await audioManager.startRecording()
        isSystemAudioActive = audioManager.isSystemAudioActive
        dkeLog("ORCH: Audio recording started, systemAudio=\(isSystemAudioActive)")

        let title = "Session \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        currentSession = dataStore.createSession(title: title, mode: mode)
        try? dataStore.save()

        isActive = true

        // Sync transcript text every second for live display
        transcriptSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.transcriptionManager.syncFromTranscribers()
                self.transcriptText = self.transcriptionManager.latestText
            }
        }

        // Generate nudges every 15 seconds
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.generateNudges() }
        }
        // Also fire once after 10 seconds so the first nudge doesn't take 15s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard self.isActive else { return }
            await self.generateNudges()
        }

        analysisTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.analyzeRecent() }
        }
    }

    func stopSession() async throws {
        analysisTimer?.invalidate()
        transcriptSyncTimer?.invalidate()
        nudgeTimer?.invalidate()
        analysisTimer = nil
        transcriptSyncTimer = nil
        nudgeTimer = nil

        transcriptionManager.stopLiveTranscription()
        try await audioManager.stopRecording()
        isActive = false
        isSystemAudioActive = false

        await analyzeRecent()
        persistTranscript()
        persistKnowledge()
        try? dataStore.save()
        currentSession = nil
    }

    private func generateNudges() async {
        guard !isGeneratingNudge else {
            dkeLog("ORCH: nudge generation already in-flight, skipping")
            return
        }
        isGeneratingNudge = true
        defer { isGeneratingNudge = false }

        let recent = transcriptionManager.latestText
        guard !recent.isEmpty else {
            dkeLog("ORCH: no transcript text yet, skipping nudge")
            return
        }
        let modelId = router.modelIdentifier(for: .nudgeGeneration) ?? "llama3.2:3b"
        dkeLog("ORCH: generateNudges — \(recent.count) chars of recent text")
        let summary = analysisEngine.extractedKnowledge.map { "[\($0.category)] \($0.content)" }.joined(separator: "\n")
        await analysisEngine.generateNudges(recentTranscript: recent, knowledgeSummary: summary, modelIdentifier: modelId)
        let newNudges = analysisEngine.currentNudges
        if !newNudges.isEmpty {
            currentNudges = newNudges
            nudgesShownAt = Date()
        }
        dkeLog("ORCH: generateNudges — got \(newNudges.count) nudges")
    }

    private func analyzeRecent() async {
        let recent = transcriptionManager.transcript.suffix(6).map {
            if let speaker = $0.speaker { "[\(speaker)] \($0.text)" } else { $0.text }
        }.joined(separator: " ")
        guard !recent.isEmpty else { return }
        let modelId = router.modelIdentifier(for: .analysis) ?? "llama3.2:3b"
        dkeLog("ORCH: analyzeRecent — \(transcriptionManager.transcript.count) segments")
        await analysisEngine.analyzeTranscript(window: recent, modelIdentifier: modelId)
        dkeLog("ORCH: analyzeRecent — \(analysisEngine.extractedKnowledge.count) knowledge atoms")
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
