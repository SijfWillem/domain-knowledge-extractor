import SwiftUI
import CoreData

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let session: SessionMO

    @State private var segments: [TranscriptSegmentMO] = []
    @State private var editedTranscript = ""
    @State private var hasChanges = false
    @State private var showExportSheet = false
    @State private var exportText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(session.title).font(.title2).bold()
                    HStack(spacing: 12) {
                        Label(session.mode.capitalized,
                              systemImage: session.mode == "virtual" ? "video" : "person.2")
                        Text(session.date, style: .date)
                        if !segments.isEmpty {
                            Text(formatDuration())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if hasChanges {
                    Button("Save") { saveChanges() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Export") { exportTranscript() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Transcript as one continuous editable text block
            if segments.isEmpty {
                ContentUnavailableView("No Transcript", systemImage: "text.alignleft",
                                       description: Text("This session has no transcript segments"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Group segments by speaker into paragraphs
                        ForEach(Array(speakerBlocks().enumerated()), id: \.offset) { _, block in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(block.speaker)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(block.speaker == "You" ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                    Text(formatTime(block.startTime) + " – " + formatTime(block.endTime))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(block.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { loadSegments() }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(text: exportText, sessionTitle: session.title)
        }
    }

    // MARK: - Speaker Blocks

    private struct SpeakerBlock {
        let speaker: String
        let text: String
        let startTime: Double
        let endTime: Double
    }

    /// Merge consecutive segments from the same speaker into blocks.
    private func speakerBlocks() -> [SpeakerBlock] {
        guard !segments.isEmpty else { return [] }
        var blocks: [SpeakerBlock] = []
        var currentSpeaker = segments[0].speaker ?? "Unknown"
        var currentTexts: [String] = [segments[0].text]
        var blockStart = segments[0].startTime
        var blockEnd = segments[0].endTime

        for segment in segments.dropFirst() {
            let speaker = segment.speaker ?? "Unknown"
            if speaker == currentSpeaker {
                currentTexts.append(segment.text)
                blockEnd = segment.endTime
            } else {
                blocks.append(SpeakerBlock(
                    speaker: currentSpeaker,
                    text: currentTexts.joined(separator: " "),
                    startTime: blockStart,
                    endTime: blockEnd
                ))
                currentSpeaker = speaker
                currentTexts = [segment.text]
                blockStart = segment.startTime
                blockEnd = segment.endTime
            }
        }
        blocks.append(SpeakerBlock(
            speaker: currentSpeaker,
            text: currentTexts.joined(separator: " "),
            startTime: blockStart,
            endTime: blockEnd
        ))
        return blocks
    }

    // MARK: - Data

    private func loadSegments() {
        let store = DataStore(context: viewContext)
        segments = (try? store.fetchTranscriptSegments(for: session)) ?? []
    }

    private func saveChanges() {
        try? viewContext.save()
        hasChanges = false
    }

    private func exportTranscript() {
        let blocks = speakerBlocks()
        let lines = blocks.map { block in
            "[\(formatTime(block.startTime))] \(block.speaker): \(block.text)"
        }
        exportText = lines.joined(separator: "\n\n")
        showExportSheet = true
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formatDuration() -> String {
        guard let first = segments.first, let last = segments.last else { return "" }
        let duration = Int(last.endTime - first.startTime)
        let mins = duration / 60
        let secs = duration % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}

private struct ExportSheet: View {
    let text: String
    let sessionTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Export Transcript").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderedProminent)

                Button("Save to File") { saveToFile() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(sessionTitle).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
