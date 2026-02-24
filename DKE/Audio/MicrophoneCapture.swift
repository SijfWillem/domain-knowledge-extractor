import AVFoundation

final class MicrophoneCapture {
    private let audioEngine = AVAudioEngine()
    private(set) var isRecording = false

    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let inputNode = audioEngine.inputNode
        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
        ) else { throw AudioError.formatCreationFailed }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: desiredFormat) { buffer, time in
            onBuffer(buffer, time)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }
}

enum AudioError: Error {
    case formatCreationFailed
    case noDisplayFound
}
