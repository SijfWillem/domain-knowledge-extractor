import ScreenCaptureKit
import CoreMedia

@available(macOS 14.0, *)
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var onAudioBuffer: ((CMSampleBuffer) -> Void)?

    func startCapture(onAudioBuffer: @escaping (CMSampleBuffer) -> Void) async throws {
        self.onAudioBuffer = onAudioBuffer
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let currentAppPID = ProcessInfo.processInfo.processIdentifier
        let currentApp = availableContent.applications.first { $0.processID == currentAppPID }
        guard let mainDisplay = availableContent.displays.first else {
            throw AudioError.noDisplayFound
        }
        let filter: SCContentFilter
        if let currentApp {
            filter = SCContentFilter(display: mainDisplay, excludingApplications: [currentApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000; config.channelCount = 1
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dke.systemaudio", qos: .userInteractive))
        try await stream.startCapture()
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        onAudioBuffer?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SCStream stopped: \(error.localizedDescription)")
    }
}
