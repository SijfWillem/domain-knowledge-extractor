import Foundation
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
final class TranscriptionManager: ObservableObject {
    @Published var transcript: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []
    @Published var latestText: String = ""

    /// Mic audio transcriber (your voice)
    let micTranscriber = SpeechTranscriber(label: "MIC")

    /// System audio transcriber (remote participants via speakers/earphones)
    let systemTranscriber = SpeechTranscriber(label: "SYS")

    func setLanguage(_ language: DKELanguage) {
        dkeLog("TXMGR: setLanguage \(language.localeIdentifier)")
        micTranscriber.setLocale(language.localeIdentifier)
        systemTranscriber.setLocale(language.localeIdentifier)
    }

    func requestAuthorization() {
        dkeLog("TXMGR: requestAuthorization")
        micTranscriber.requestAuthorization()
        // Both use the same Speech framework authorization — one call is enough,
        // but calling on both ensures both have isAuthorized set
        systemTranscriber.requestAuthorization()
    }

    func startLiveTranscription(includeSystemAudio: Bool) {
        dkeLog("TXMGR: startLiveTranscription, includeSystemAudio=\(includeSystemAudio)")
        micTranscriber.startRecognition()
        if includeSystemAudio {
            systemTranscriber.startRecognition()
        }
    }

    func stopLiveTranscription() {
        dkeLog("TXMGR: stopLiveTranscription")
        micTranscriber.stopRecognition()
        systemTranscriber.stopRecognition()
        syncFromTranscribers()
    }

    /// Merge transcripts from both mic and system audio transcribers, sorted by time.
    func syncFromTranscribers() {
        var merged: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []

        for segment in micTranscriber.transcript {
            merged.append((text: segment.text, speaker: "You", startTime: segment.startTime, endTime: segment.endTime))
        }
        for segment in systemTranscriber.transcript {
            merged.append((text: segment.text, speaker: "Remote", startTime: segment.startTime, endTime: segment.endTime))
        }

        merged.sort { $0.startTime < $1.startTime }
        transcript = merged

        // Show latest text from whichever transcriber was most recently active
        let micText = micTranscriber.latestText
        let sysText = systemTranscriber.latestText
        if sysText.count > micText.count {
            latestText = sysText
        } else {
            latestText = micText
        }
    }
}
