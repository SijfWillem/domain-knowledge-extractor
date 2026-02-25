import Foundation
import Speech
import AVFoundation

/// Real-time speech transcription using Apple's Speech framework (SFSpeechRecognizer).
/// Works offline on macOS 14+ with downloaded language models.
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []
    @Published var latestText: String = ""
    @Published var isAuthorized = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionStartTime: Date?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAuthorized = (status == .authorized)
            }
        }
    }

    /// Start a recognition session. Feed audio buffers via `appendAudioBuffer(_:)`.
    func startRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        // Cancel any existing task
        stopRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        sessionStartTime = Date()
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.latestText = String(text.suffix(100))

                    // Extract segments from the transcription
                    let segments = result.bestTranscription.segments
                    if let lastSegment = segments.last {
                        let startTime = lastSegment.timestamp
                        let endTime = startTime + lastSegment.duration
                        let segmentText = lastSegment.substring

                        // Only add new segments we haven't seen
                        if !segmentText.isEmpty && !self.transcript.contains(where: {
                            abs($0.startTime - startTime) < 0.1 && $0.text == segmentText
                        }) {
                            self.transcript.append((
                                text: segmentText,
                                speaker: nil,
                                startTime: startTime,
                                endTime: endTime
                            ))
                        }
                    }
                }

                if let error {
                    print("Recognition error: \(error.localizedDescription)")
                }

                if result?.isFinal == true {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            }
        }
    }

    /// Feed an audio buffer from AVAudioEngine into the recognizer.
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
