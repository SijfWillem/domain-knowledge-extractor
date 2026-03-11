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

/// Captures microphone audio using AVCaptureSession instead of AVAudioEngine.
/// AVCaptureSession does NOT take over the audio hardware, so system audio
/// (music, meetings, etc.) continues to play normally through speakers/headphones.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "com.dke.micCapture", qos: .userInteractive)
    private(set) var isRecording = false

    private var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var bufferCount = 0

    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        self.onBuffer = onBuffer
        bufferCount = 0

        captureSession.beginConfiguration()

        // Prefer built-in microphone over Bluetooth mic to avoid triggering HFP
        // (Hands-Free Profile), which downgrades Bluetooth audio to 8kHz mono.
        let micDevice: AVCaptureDevice
        if let builtIn = Self.findBuiltInMic() {
            micDevice = builtIn
            dkeLog("MIC: Using built-in mic: \(builtIn.localizedName)")
        } else if let fallback = AVCaptureDevice.default(for: .audio) {
            micDevice = fallback
            dkeLog("MIC: No built-in mic found, using default: \(fallback.localizedName)")
        } else {
            dkeLog("MIC: No audio capture device found")
            throw AudioError.formatCreationFailed
        }
        let micInput = try AVCaptureDeviceInput(device: micDevice)
        guard captureSession.canAddInput(micInput) else {
            dkeLog("MIC: Cannot add mic input to session")
            throw AudioError.formatCreationFailed
        }
        captureSession.addInput(micInput)

        // Add audio data output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(audioOutput) else {
            dkeLog("MIC: Cannot add audio output to session")
            throw AudioError.formatCreationFailed
        }
        captureSession.addOutput(audioOutput)

        captureSession.commitConfiguration()
        captureSession.startRunning()
        isRecording = true
        dkeLog("MIC: AVCaptureSession started successfully")
    }

    func stopCapture() {
        captureSession.stopRunning()
        // Remove all inputs/outputs so the session can be reused
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }
        isRecording = false
        onBuffer = nil
        dkeLog("MIC: Stopped")
    }

    // MARK: - Device Selection

    /// Finds the built-in microphone, avoiding Bluetooth devices that would trigger HFP.
    private static func findBuiltInMic() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices.first
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pcmBuffer = Self.convertToPCMBuffer(sampleBuffer) else { return }

        bufferCount += 1
        if bufferCount == 1 || bufferCount % 200 == 0 {
            dkeLog("MIC: Buffer #\(bufferCount), frames=\(pcmBuffer.frameLength), sampleRate=\(pcmBuffer.format.sampleRate)")
        }

        let time = AVAudioTime(sampleTime: 0, atRate: pcmBuffer.format.sampleRate)
        onBuffer?(pcmBuffer, time)
    }

    /// Convert CMSampleBuffer to AVAudioPCMBuffer for SFSpeechRecognizer compatibility.
    private static func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        var mutableASBD = asbd
        guard let avFormat = AVAudioFormat(streamDescription: &mutableASBD) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else {
            return nil
        }
        pcmBuffer.frameLength = frameCount

        guard let blockBuffer = sampleBuffer.dataBuffer else { return nil }
        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard let destPtr = pcmBuffer.audioBufferList.pointee.mBuffers.mData else { return nil }

        let status = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: destPtr)
        guard status == noErr else { return nil }

        return pcmBuffer
    }
}

enum AudioError: Error {
    case formatCreationFailed
    case noDisplayFound
}
