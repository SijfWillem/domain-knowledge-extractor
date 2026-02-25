import Foundation
import AVFoundation

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var transcript: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []
    @Published var latestText: String = ""

    let speechTranscriber = SpeechTranscriber()

    func requestAuthorization() {
        speechTranscriber.requestAuthorization()
    }

    func startLiveTranscription() {
        speechTranscriber.startRecognition()
    }

    func stopLiveTranscription() {
        speechTranscriber.stopRecognition()
        // Copy final results
        transcript = speechTranscriber.transcript
        latestText = speechTranscriber.latestText
    }

    /// Feed a raw audio buffer from AVAudioEngine to the speech recognizer.
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        speechTranscriber.appendAudioBuffer(buffer)
        // Sync published properties
        transcript = speechTranscriber.transcript
        latestText = speechTranscriber.latestText
    }
}
