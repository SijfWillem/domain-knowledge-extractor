import Foundation
import whisper

enum WhisperError: Error {
    case couldNotInitializeContext
    case couldNotProcessAudio
    case modelNotFound
}

actor WhisperContext {
    private var context: OpaquePointer

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.couldNotInitializeContext
        }
        self.context = ctx
    }

    deinit { whisper_free(context) }

    func transcribe(samples: [Float]) throws -> [(text: String, start: Int64, end: Int64)] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_special = false
        params.print_timestamps = true
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let languageCString = strdup("auto")
        defer { free(languageCString) }
        params.language = languageCString

        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        if result != 0 { throw WhisperError.couldNotProcessAudio }

        var segments: [(String, Int64, Int64)] = []
        let nSegments = whisper_full_n_segments(context)
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(context, i) {
                let text = String(cString: cStr)
                let start = whisper_full_get_segment_t0(context, i)
                let end = whisper_full_get_segment_t1(context, i)
                segments.append((text, start, end))
            }
        }
        return segments
    }
}
