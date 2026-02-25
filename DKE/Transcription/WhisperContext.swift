import Foundation

enum WhisperError: Error {
    case notAvailable
}

/// Placeholder for future whisper.cpp integration.
/// Currently transcription is handled by SpeechTranscriber using Apple's Speech framework.
actor WhisperContext {
    init(modelPath: String) throws {
        throw WhisperError.notAvailable
    }

    func transcribe(samples: [Float]) throws -> [(text: String, start: Int64, end: Int64)] {
        throw WhisperError.notAvailable
    }
}
