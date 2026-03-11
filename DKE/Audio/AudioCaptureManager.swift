import Foundation
import AVFoundation
import CoreMedia

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
final class AudioCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var isSystemAudioActive = false
    @Published var mode: SessionMode = .inPerson

    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    let chunker = AudioChunker()

    /// Mic audio buffer callback (AVAudioPCMBuffer from AVAudioEngine)
    var onRawAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// System audio buffer callback (AVAudioPCMBuffer converted from CMSampleBuffer)
    var onSystemAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func startRecording() async throws {
        dkeLog("AUDIOMGR: startRecording mode=\(mode)")

        // Always start mic capture
        try micCapture.startCapture { [weak self] buffer, _ in
            self?.onRawAudioBuffer?(buffer)
            self?.chunker.process(buffer: buffer)
        }

        // For virtual mode, also capture system audio
        if mode == .virtual {
            do {
                try await systemCapture.startCapture { [weak self] sampleBuffer in
                    self?.chunker.process(sampleBuffer: sampleBuffer)
                    // Convert CMSampleBuffer → AVAudioPCMBuffer for speech recognition
                    if let pcmBuffer = Self.convertToPCMBuffer(sampleBuffer) {
                        self?.onSystemAudioBuffer?(pcmBuffer)
                    }
                }
                isSystemAudioActive = true
                dkeLog("AUDIOMGR: System audio capture started")
            } catch {
                isSystemAudioActive = false
                dkeLog("AUDIOMGR: System audio capture failed (non-fatal): \(error). Mic-only mode.")
            }
        }

        isRecording = true
        dkeLog("AUDIOMGR: Recording started")
    }

    func stopRecording() async throws {
        micCapture.stopCapture()
        if mode == .virtual {
            try? await systemCapture.stopCapture()
        }
        chunker.flush()
        isRecording = false
        isSystemAudioActive = false
    }

    private static var sysConvertCount = 0
    /// Lazily created converter for downsampling system audio to 16kHz mono for speech recognition.
    private static var audioConverter: AVAudioConverter?
    private static let speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// Convert CMSampleBuffer (from ScreenCaptureKit at 48kHz stereo) to
    /// AVAudioPCMBuffer at 16kHz mono for SFSpeechRecognizer.
    static func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription else { return nil }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else { return nil }

        sysConvertCount += 1

        var mutableASBD = asbd
        guard let sourceFormat = AVAudioFormat(streamDescription: &mutableASBD) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return nil }

        // Create source buffer matching ScreenCaptureKit's native format
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return nil }
        sourceBuffer.frameLength = frameCount

        guard let blockBuffer = sampleBuffer.dataBuffer else { return nil }
        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard let destPtr = sourceBuffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        let status = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: destPtr)
        guard status == noErr else { return nil }

        // If already at 16kHz mono, return directly
        if sourceFormat.sampleRate == 16000 && sourceFormat.channelCount == 1 {
            return sourceBuffer
        }

        // Downsample to 16kHz mono for speech recognition
        if audioConverter == nil || audioConverter?.inputFormat != sourceFormat {
            audioConverter = AVAudioConverter(from: sourceFormat, to: speechFormat)
            if sysConvertCount <= 2 {
                dkeLog("CONVERT: Created converter \(sourceFormat.sampleRate)Hz/\(sourceFormat.channelCount)ch → 16kHz/1ch")
            }
        }
        guard let converter = audioConverter else { return nil }

        let ratio = speechFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: outputFrameCount) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error {
            if sysConvertCount <= 2 { dkeLog("CONVERT: Conversion error: \(error)") }
            return nil
        }

        if sysConvertCount == 1 {
            dkeLog("CONVERT: Success — \(frameCount) frames @ \(sourceFormat.sampleRate)Hz → \(outputBuffer.frameLength) frames @ 16kHz mono")
        }
        return outputBuffer
    }
}
