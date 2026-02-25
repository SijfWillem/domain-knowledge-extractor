import Foundation
import AVFoundation

@MainActor
final class AudioCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var mode: SessionMode = .inPerson

    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    let chunker = AudioChunker()

    /// Raw audio buffer callback for speech recognition
    var onRawAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func startRecording() async throws {
        switch mode {
        case .inPerson:
            try micCapture.startCapture { [weak self] buffer, _ in
                self?.onRawAudioBuffer?(buffer)
                self?.chunker.process(buffer: buffer)
            }
        case .virtual:
            try micCapture.startCapture { [weak self] buffer, _ in
                self?.onRawAudioBuffer?(buffer)
                self?.chunker.process(buffer: buffer)
            }
            try await systemCapture.startCapture { [weak self] sampleBuffer in
                self?.chunker.process(sampleBuffer: sampleBuffer)
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
