import SwiftUI
import AppKit

@main
struct DKEApp: App {
    @StateObject private var router: LLMRouter
    @StateObject private var orchestrator: SessionOrchestrator

    private let widgetPanel = FloatingWidgetPanel()

    init() {
        let r = LLMRouter()
        _router = StateObject(wrappedValue: r)
        _orchestrator = StateObject(wrappedValue: SessionOrchestrator(router: r))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(orchestrator: orchestrator, router: router, onStartSession: showWidget)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        }
        Settings {
            SettingsView(router: router, orchestrator: orchestrator)
        }
    }

    private func showWidget() {
        let hostingView = NSHostingView(rootView: FloatingWidgetView(orchestrator: orchestrator))
        widgetPanel.contentView = hostingView
        widgetPanel.orderFront(nil)
    }
}
