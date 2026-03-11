import Foundation
import Speech
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

/// Real-time speech transcription using Apple's Speech framework (SFSpeechRecognizer).
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []
    @Published var latestText: String = ""
    @Published var isAuthorized = false

    let label: String
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionStartTime: Date?
    private var isStopped = false
    private var consecutiveRestarts = 0

    nonisolated(unsafe) private var _recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var _appendCount = 0

    /// Stores the latest partial result so we can flush it when stopping or restarting.
    private var lastPartialResult: SFSpeechRecognitionResult?

    init(label: String = "MIC") {
        self.label = label
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: DKELanguage.current.localeIdentifier))
    }

    func setLocale(_ identifier: String) {
        dkeLog("[\(label)] Changing locale to \(identifier)")
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    func requestAuthorization() {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .authorized {
            dkeLog("[\(label)] Already authorized")
            isAuthorized = true
            return
        }
        if currentStatus == .denied || currentStatus == .restricted {
            dkeLog("[\(label)] Authorization denied/restricted")
            isAuthorized = false
            return
        }
        dkeLog("[\(label)] Requesting speech authorization...")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            dkeLog("[\(self.label)] Authorization: \(status.rawValue)")
            Task { @MainActor in
                self.isAuthorized = (status == .authorized)
            }
        }
    }

    func startRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            dkeLog("[\(label)] ERROR - Recognizer unavailable")
            return
        }

        isStopped = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // Atomic swap — no gap where audio is dropped
        let oldRequest = _recognitionRequest
        _recognitionRequest = request
        _appendCount = 0

        oldRequest?.endAudio()
        recognitionTask?.cancel()
        sessionStartTime = Date()

        dkeLog("[\(label)] Starting recognition...")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.isStopped else { return }

                if let result {
                    self.consecutiveRestarts = 0
                    let fullText = result.bestTranscription.formattedString
                    self.latestText = String(fullText.suffix(200))
                    dkeLog("[\(self.label)] TRANSCRIPT: '\(fullText.suffix(80))'")

                    if result.isFinal {
                        self.lastPartialResult = nil
                        self.commitText(from: result)
                    } else {
                        self.lastPartialResult = result
                    }
                }

                if let error {
                    let desc = error.localizedDescription
                    dkeLog("[\(self.label)] Error: \(desc)")

                    // Flush any partial text before restarting
                    self.flushPartialText()

                    if desc.contains("No speech detected") || desc.contains("retry") {
                        self.consecutiveRestarts += 1
                        let delay = min(pow(2.0, Double(self.consecutiveRestarts - 1)), 10.0)
                        dkeLog("[\(self.label)] Restart #\(self.consecutiveRestarts) in \(delay)s")
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(delay))
                            guard !self.isStopped else { return }
                            self.startRecognition()
                        }
                        return
                    } else {
                        dkeLog("[\(self.label)] Permanent error — NOT restarting")
                    }
                }

                if result?.isFinal == true {
                    dkeLog("[\(self.label)] Final — restarting")
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !self.isStopped else { return }
                        self.startRecognition()
                    }
                }
            }
        }
        dkeLog("[\(label)] Recognition task created")
    }

    /// Thread-safe: called directly from the audio thread.
    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let request = _recognitionRequest else { return }
        _appendCount += 1
        // Log first buffer and periodically to verify audio is reaching recognizer
        if _appendCount == 1 || _appendCount % 500 == 0 {
            var rms: Float = 0
            if let channelData = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count { sum += channelData[i] * channelData[i] }
                rms = sqrtf(sum / Float(max(count, 1)))
            }
            dkeLog("[\(label)] appendBuffer #\(_appendCount), frames=\(buffer.frameLength), RMS=\(rms), \(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch")
        }
        request.append(buffer)
    }

    /// Commits a final recognition result as a transcript segment.
    /// Converts the recognizer's relative timestamps to wall-clock offsets
    /// so segments from different recognition sessions sort correctly.
    private func commitText(from result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // sessionStartTime is the wall-clock time when this recognition session began.
        // The recognizer's timestamps are relative to the start of each session,
        // so we add the session offset to get consistent ordering across restarts.
        let sessionOffset = sessionStartTime?.timeIntervalSinceReferenceDate ?? 0

        let wordSegments = result.bestTranscription.segments
        let startTime = sessionOffset + (wordSegments.first?.timestamp ?? 0)
        let lastSeg = wordSegments.last
        let endTime = sessionOffset + (lastSeg?.timestamp ?? 0) + (lastSeg?.duration ?? 0)

        transcript.append((text: text, speaker: nil, startTime: startTime, endTime: endTime))
        dkeLog("[\(label)] COMMITTED segment (offset \(Int(sessionOffset))): \(text.prefix(80))...")
    }

    /// Flushes the last partial result (if any) as a transcript segment.
    private func flushPartialText() {
        guard let result = lastPartialResult else { return }
        lastPartialResult = nil
        commitText(from: result)
    }

    func stopRecognition() {
        isStopped = true
        flushPartialText()
        _recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        _recognitionRequest = nil
        recognitionTask = nil
        dkeLog("[\(label)] Stopped")
    }
}
