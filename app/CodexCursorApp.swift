import SwiftUI

@main
struct CodexCursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Codex Cursor") {
            CompanionPanel()
                .environmentObject(appState)
                .frame(minWidth: 460, idealWidth: 560, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
