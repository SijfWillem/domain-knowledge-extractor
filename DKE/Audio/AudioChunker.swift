import AVFoundation
import CoreMedia
import os

final class AudioChunker: @unchecked Sendable {
    private let chunkDuration: TimeInterval
    private let sampleRate: Double
    private var accumulatedSamples: [Float] = []
    private let samplesPerChunk: Int
    private let lock = os.OSAllocatedUnfairLock()

    var onChunkReady: (([Float]) -> Void)?

    init(chunkDuration: TimeInterval = 5.0, sampleRate: Double = 16000) {
        self.chunkDuration = chunkDuration
        self.sampleRate = sampleRate
        self.samplesPerChunk = Int(sampleRate * chunkDuration)
    }

    func process(buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))
        lock.withLock { accumulatedSamples.append(contentsOf: samples) }
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
        lock.withLock { accumulatedSamples.append(contentsOf: samples) }
        emitChunksIfReady()
    }

    func flush() {
        let chunk: [Float]? = lock.withLock {
            guard !accumulatedSamples.isEmpty else { return nil }
            if accumulatedSamples.count < samplesPerChunk {
                accumulatedSamples.append(contentsOf: [Float](repeating: 0.0, count: samplesPerChunk - accumulatedSamples.count))
            }
            let c = Array(accumulatedSamples.prefix(samplesPerChunk))
            accumulatedSamples.removeAll()
            return c
        }
        if let chunk { onChunkReady?(chunk) }
    }

    private func emitChunksIfReady() {
        while true {
            let chunk: [Float]? = lock.withLock {
                guard accumulatedSamples.count >= samplesPerChunk else { return nil }
                let c = Array(accumulatedSamples.prefix(samplesPerChunk))
                accumulatedSamples.removeFirst(samplesPerChunk)
                return c
            }
            guard let chunk else { break }
            onChunkReady?(chunk)
        }
    }
}
