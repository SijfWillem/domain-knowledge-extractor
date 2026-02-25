import SwiftUI

struct ContentView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    @ObservedObject var router: LLMRouter

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    KnowledgeBrowserView()
                } label: {
                    Label("Knowledge Base", systemImage: "brain")
                }
                NavigationLink {
                    SettingsView(router: router)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("DKE")
        } detail: {
            KnowledgeBrowserView()
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
