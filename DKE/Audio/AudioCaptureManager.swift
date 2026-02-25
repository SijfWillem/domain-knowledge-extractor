import Foundation
import AVFoundation

@MainActor
final class AudioCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var mode: SessionMode = .inPerson

    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    let chunker = AudioChunker()

    func startRecording() async throws {
        switch mode {
        case .inPerson:
            try micCapture.startCapture { [chunker] buffer, _ in
                chunker.process(buffer: buffer)
            }
        case .virtual:
            try micCapture.startCapture { [chunker] buffer, _ in
                chunker.process(buffer: buffer)
            }
            try await systemCapture.startCapture { [chunker] sampleBuffer in
                chunker.process(sampleBuffer: sampleBuffer)
            }
        }
        isRecording = true
    }

    func stopRecording() async throws {
        micCapture.stopCapture()
        if mode == .virtual {
            try await systemCapture.stopCapture()
        }
        chunker.flush()
        isRecording = false
    }
}
