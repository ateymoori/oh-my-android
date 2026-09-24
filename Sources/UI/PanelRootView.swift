import SwiftUI

struct PanelRootView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 8) {
            HeaderView()
            DeviceInfoView()
            content
        }
        .padding(12)
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelCorner)
                .strokeBorder(Theme.accent, lineWidth: isDropTargeted ? 3 : 0)
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        }
        .overlay(alignment: .bottom) { ToastView(toast: model.features.toast).padding(.bottom, 14) }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .task(id: model.devices?.selected) { await model.reload() }
        // The device can change on its own (Android settings, Studio). Re-read when attention returns, not on a timer.
        .onHover { inside in if inside { Task { await model.reloadIfStale() } } }
    }

    @ViewBuilder
    private var content: some View {
        if model.sdk == nil {
            ContentUnavailableView {
                Label("Android SDK Not Found", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Install Android Studio or Android platform-tools, or choose the SDK folder in Settings.")
            } actions: {
                Button("Open Settings…") {
                    NSApp.activate()
                    openSettings()
                }
            }
        } else if let context = model.context {
            FeatureGridView(context: context)
        } else if model.devices?.hasOnlyUnreadyDevices == true {
            ContentUnavailableView {
                Label("Device Not Ready", systemImage: "iphone.slash")
            } description: {
                Text("adb reports it \(model.devices?.devices.first?.state.rawValue ?? "offline"). Re-checking every few seconds.")
            } actions: {
                Button("Restart adb") { Task { await model.devices?.restartServer() } }
            }
        } else {
            ContentUnavailableView {
                Label("No Device", systemImage: "iphone.slash")
            } description: {
                Text(model.devices?.lastError.map { "adb: \($0)" } ?? "Start an emulator or connect a device with USB debugging on.")
            } actions: {
                Button("Restart adb") { Task { await model.devices?.restartServer() } }
            }
        }
    }

    /// APK: install. PNG/JPEG: open the Layout Inspector with the image as design overlay.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        FileDrop.load(providers, extensions: ["apk"] + FileDrop.imageExtensions) { url in
            guard let context = model.context else { return }
            if url.pathExtension.lowercased() == "apk" {
                model.features.install(url, context)
            } else {
                model.host.openLayoutInspector(context, url)
            }
        }
    }
}
