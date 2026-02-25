import Foundation

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var transcript: [(text: String, speaker: String?, startTime: Double, endTime: Double)] = []
    @Published var latestText: String = ""

    private var whisperContext: WhisperContext?
    private var elapsedSeconds: Double = 0

    func loadModel(path: String) async throws {
        whisperContext = try WhisperContext(modelPath: path)
    }

    func processChunk(_ samples: [Float]) {
        guard let ctx = whisperContext else { return }
        let chunkStart = elapsedSeconds
        elapsedSeconds += Double(samples.count) / 16000.0

        Task {
            do {
                let segments = try await ctx.transcribe(samples: samples)
                await MainActor.run {
                    for segment in segments {
                        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        let startTime = chunkStart + Double(segment.start) / 100.0
                        let endTime = chunkStart + Double(segment.end) / 100.0
                        transcript.append((text: text, speaker: nil, startTime: startTime, endTime: endTime))
                        latestText = text
                    }
                }
            } catch {
                print("Transcription error: \(error)")
            }
        }
    }
}
