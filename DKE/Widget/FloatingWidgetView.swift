import SwiftUI

struct FloatingWidgetView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    @ObservedObject var audioManager: AudioCaptureManager

    /// Nudges the user has pinned by clicking
    @State private var pinnedNudges: [NudgeSuggestion] = []
    /// Track which new nudges we've already added to avoid duplicates
    @State private var seenQuestions: Set<String> = []

    init(orchestrator: SessionOrchestrator) {
        self.orchestrator = orchestrator
        self.audioManager = orchestrator.audioManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(orchestrator.isActive ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                Text(orchestrator.isActive ? "Recording" : "Ready")
                    .font(.caption.bold())
                Spacer()
                if !pinnedNudges.isEmpty {
                    Button("Clear") {
                        pinnedNudges.removeAll()
                        seenQuestions.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            if !orchestrator.isActive {
                Picker("Mode", selection: $audioManager.mode) {
                    Text("In-Person").tag(SessionMode.inPerson)
                    Text("Virtual").tag(SessionMode.virtual)
                }
                .pickerStyle(.segmented)
            }

            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: orchestrator.isActive ? "stop.fill" : "record.circle")
                    Text(orchestrator.isActive ? "Stop" : "Record")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if orchestrator.isActive && (!orchestrator.currentNudges.isEmpty || !pinnedNudges.isEmpty) {
                Divider()
                Text("Ask:")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // New (unpinned) nudges at the top
                        ForEach(Array(unpinnedNudges.enumerated()), id: \.offset) { _, nudge in
                            NudgeRow(nudge: nudge, isPinned: false)
                                .onTapGesture { pinNudge(nudge) }
                        }

                        // Pinned nudges below (newest first)
                        ForEach(Array(pinnedNudges.enumerated()), id: \.offset) { _, nudge in
                            NudgeRow(nudge: nudge, isPinned: true)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            if orchestrator.isActive && !orchestrator.transcriptText.isEmpty {
                Text(orchestrator.transcriptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    /// Nudges from the orchestrator that haven't been pinned yet
    private var unpinnedNudges: [NudgeSuggestion] {
        orchestrator.currentNudges.filter { nudge in
            !seenQuestions.contains(nudge.question)
        }
    }

    private func pinNudge(_ nudge: NudgeSuggestion) {
        guard !seenQuestions.contains(nudge.question) else { return }
        seenQuestions.insert(nudge.question)
        pinnedNudges.insert(nudge, at: 0)
    }

    private func toggleRecording() {
        Task {
            if orchestrator.isActive {
                try? await orchestrator.stopSession()
                pinnedNudges.removeAll()
                seenQuestions.removeAll()
            } else {
                try? await orchestrator.startSession(mode: audioManager.mode)
            }
        }
    }
}

private struct NudgeRow: View {
    let nudge: NudgeSuggestion
    let isPinned: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡")
                .font(.body)
            Text(nudge.question)
                .font(.body)
            Spacer()
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPinned ? Color.accentColor.opacity(0.05) : Color.accentColor.opacity(0.1))
        .cornerRadius(10)
    }
}
