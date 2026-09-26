import SwiftUI
import AppKit

@main
struct StaleApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 640, minHeight: 500)
        }
        .defaultSize(width: 780, height: 640)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
