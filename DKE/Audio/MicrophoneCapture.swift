import AVFoundation

final class MicrophoneCapture {
    private let audioEngine = AVAudioEngine()
    private(set) var isRecording = false

    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, time in
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
