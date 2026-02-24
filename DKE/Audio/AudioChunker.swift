import AVFoundation
import CoreMedia

final class AudioChunker {
    private let chunkDuration: TimeInterval
    private let sampleRate: Double
    private var accumulatedSamples: [Float] = []
    private let samplesPerChunk: Int

    var onChunkReady: (([Float]) -> Void)?

    init(chunkDuration: TimeInterval = 5.0, sampleRate: Double = 16000) {
        self.chunkDuration = chunkDuration
        self.sampleRate = sampleRate
        self.samplesPerChunk = Int(sampleRate * chunkDuration)
    }

    func process(buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))
        accumulatedSamples.append(contentsOf: samples)
        emitChunksIfReady()
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        let floatCount = length / MemoryLayout<Float>.size
        let samples: [Float] = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(floatCount))
        }
        accumulatedSamples.append(contentsOf: samples)
        emitChunksIfReady()
    }

    func flush() {
        guard !accumulatedSamples.isEmpty else { return }
        if accumulatedSamples.count < samplesPerChunk {
            accumulatedSamples.append(contentsOf: [Float](repeating: 0.0, count: samplesPerChunk - accumulatedSamples.count))
        }
        let chunk = Array(accumulatedSamples.prefix(samplesPerChunk))
        accumulatedSamples.removeAll()
        onChunkReady?(chunk)
    }

    private func emitChunksIfReady() {
        while accumulatedSamples.count >= samplesPerChunk {
            let chunk = Array(accumulatedSamples.prefix(samplesPerChunk))
            accumulatedSamples.removeFirst(samplesPerChunk)
            onChunkReady?(chunk)
        }
    }
}
