import SwiftUI

struct ContentView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    @ObservedObject var router: LLMRouter
    var onStartSession: () -> Void

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    SessionHistoryView()
                } label: {
                    Label("Sessions", systemImage: "waveform")
                }
                NavigationLink {
                    KnowledgeBrowserView()
                } label: {
                    Label("Knowledge Base", systemImage: "brain")
                }
                NavigationLink {
                    SettingsView(router: router, orchestrator: orchestrator)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("DKE")
            .safeAreaInset(edge: .bottom) {
                Button(action: onStartSession) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("New Session")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        } detail: {
            SessionHistoryView()
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
