import SwiftUI

@main
struct OyamaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Oyama", systemImage: "mountain.2.fill") {
            MenuBarContent(delegate: delegate)
        }
        Settings {
            SettingsView().environment(delegate.model)
        }
    }
}

private struct MenuBarContent: View {
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Show/Hide Panel") { delegate.panel?.toggle() }
        Divider()
        Button("Layout Inspector…") { delegate.openLayoutInspector() }
            .disabled(delegate.model.context == nil)
        Button("Data Inspector…") { delegate.openDataInspector() }
            .disabled(delegate.model.context == nil)
        Divider()
        Button("Restart adb") { Task { await delegate.model.devices?.restartServer() } }
            .disabled(delegate.model.devices == nil)
        Divider()
        Button("Settings…") {
            NSApp.activate()  // otherwise the window opens behind the frontmost app
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Oyama") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
