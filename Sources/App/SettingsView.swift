import ServiceManagement
import SwiftUI

struct SettingsView: View {
    /// Shared with the menu, which opens the AI Agents tab directly.
    static let tabKey = "settings.tab"
    @AppStorage(SettingsView.tabKey) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AgentSettingsView()
                .tabItem { Label("AI Agents", systemImage: "sparkles") }
                .tag("agents")
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var chosenSDK: URL?
    @State private var error: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Android SDK") {
                    HStack {
                        Text(model.sdk?.root.path ?? "Not found")
                            .foregroundStyle(model.sdk == nil ? .red : .secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseSDK)
                    }
                }
                if chosenSDK != nil {
                    LabeledContent("Relaunch to use the new SDK.") {
                        Button("Relaunch", action: relaunch)
                    }
                }
            } footer: {
                Text("Looked up in ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk and Homebrew's android-commandlinetools.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Dock panel beside the emulator window", isOn: $model.dockToEmulator)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                LabeledContent("Captures") {
                    HStack {
                        Text(CaptureLocation.directory.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: CaptureLocation.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([CaptureLocation.directory])
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseSDK() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the Android SDK folder (it contains platform-tools)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard AndroidSDK.isValid(AndroidSDK(root: url)) else {
            error = "No platform-tools/adb in \(url.path)."
            return
        }
        error = nil
        UserDefaults.standard.set(url.path, forKey: AndroidSDK.customRootKey)
        chosenSDK = url
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
