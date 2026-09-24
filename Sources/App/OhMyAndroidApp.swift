import SwiftUI

@main
struct OhMyAndroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(delegate: delegate)
        } label: {
            Image("MenuBarIcon").accessibilityLabel("Oh My Android")
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
        Button("Quit Oh My Android") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
