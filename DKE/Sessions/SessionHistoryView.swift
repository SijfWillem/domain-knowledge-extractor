import SwiftUI
import CoreData

struct SessionHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var sessions: [SessionMO] = []
    @State private var sessionToDelete: SessionMO?

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions Yet", systemImage: "waveform",
                                       description: Text("Record a meeting to see it here"))
            } else {
                List {
                    ForEach(sessions, id: \.id) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HStack {
                                SessionRow(session: session)
                                Spacer()
                                Button(role: .destructive) {
                                    sessionToDelete = session
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .onAppear { loadSessions() }
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            if let session = sessionToDelete {
                Text("Delete \"\(session.title)\" and all its data?")
            }
        }
    }

    private func loadSessions() {
        let store = DataStore(context: viewContext)
        sessions = (try? store.fetchAllSessions()) ?? []
    }

    private func deleteSession(_ session: SessionMO) {
        let store = DataStore(context: viewContext)
        store.deleteSession(session)
        try? store.save()
        loadSessions()
    }
}

private struct SessionRow: View {
    let session: SessionMO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
            HStack {
                Label(session.mode.capitalized, systemImage: session.mode == "virtual" ? "video" : "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Show transcript preview
            let preview = transcriptPreview()
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func transcriptPreview() -> String {
        let segments = session.segmentsArray
        guard !segments.isEmpty else { return "" }
        return segments.map(\.text).joined(separator: " ").prefix(150) + "..."
    }
}
