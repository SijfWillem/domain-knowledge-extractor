import SwiftUI

struct FloatingWidgetView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    @ObservedObject var audioManager: AudioCaptureManager

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

            if orchestrator.isActive && !orchestrator.currentNudges.isEmpty {
                Divider()
                Text("Ask:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(Array(orchestrator.currentNudges.prefix(2).enumerated()), id: \.offset) { _, nudge in
                    Text(nudge.question)
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if orchestrator.isActive && !orchestrator.transcriptText.isEmpty {
                Text(orchestrator.transcriptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func toggleRecording() {
        Task {
            if orchestrator.isActive {
                try? await orchestrator.stopSession()
            } else {
                try? await orchestrator.startSession(mode: audioManager.mode)
            }
        }
    }
}
