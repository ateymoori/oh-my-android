import SwiftUI

struct PanelRootView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            HeaderView()
            DeviceInfoView()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelCorner)
                .strokeBorder(Theme.accent, lineWidth: isDropTargeted ? 3 : 0)
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        }
        .overlay(alignment: .bottom) { ToastView(toast: model.features.toast).padding(.bottom, 14) }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .task(id: model.devices?.selected) { await model.reload() }
        .task { await model.emulators?.reload() }
        .onChange(of: model.devices?.devices ?? []) { _, devices in model.emulators?.devicesChanged(devices) }
        // The device can change on its own (Android settings, Studio). Re-read when attention returns, not on a timer.
        .onHover { inside in if inside { Task { await model.reloadIfStale() } } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.panelState {
        case .ready(let context):
            FeatureGridView(context: context)
        case .sdkMissing:
            PanelMessage(symbol: "exclamationmark.triangle", title: "Android SDK Not Found",
                         message: "Install Android Studio, or choose the folder of your Android SDK.", tint: .orange) {
                PanelMessageButton(title: "Choose SDK…") {
                    NSApp.activate()
                    openSettings()
                }
                Link("Get Android Studio", destination: URL(string: "https://developer.android.com/studio")!)
                    .font(.callout)
            }
        case .adbFailed(let error):
            PanelMessage(symbol: "exclamationmark.triangle", title: "adb Not Responding",
                         message: "Restart adb. If it keeps failing, restart the emulator or reconnect the phone.",
                         detail: error, tint: .orange) {
                PanelMessageButton(title: "Restart adb", symbol: "arrow.clockwise", action: restartADB)
            }
        case .starting(let avd):
            PanelMessage(symbol: nil, title: "Starting Emulator",
                         message: "\(EmulatorLauncher.displayName(avd)) is booting. This can take a minute.")
        case .booting(let device):
            PanelMessage(symbol: nil, title: "Starting \(device.displayName)", message: "Waiting for Android to finish booting.") {
                restartLink
            }
        case .unauthorized(let device):
            PanelMessage(symbol: "hand.raised", title: "Allow USB Debugging",
                         message: "Unlock \(device.displayName) and tap Allow in the USB debugging prompt.") {
                restartLink
            }
        case .offline(let device):
            PanelMessage(symbol: "cable.connector.slash", title: "Device Offline",
                         message: "\(device.displayName) does not respond. Reconnect the cable, or restart adb.") {
                PanelMessageButton(title: "Restart adb", symbol: "arrow.clockwise", action: restartADB)
            }
        case .noDevice:
            noDevice
        }
    }

    private var noDevice: some View {
        let avds = model.emulators?.avds ?? []
        return PanelMessage(
            symbol: "iphone.slash", title: "No Device",
            message: avds.isEmpty
                ? "Create an emulator in Android Studio's Device Manager, or connect a phone with USB debugging on."
                : "Start an emulator, or connect a phone with USB debugging on."
        ) {
            ForEach(avds.prefix(Self.visibleAVDs), id: \.self) { avd in
                PanelMessageButton(title: EmulatorLauncher.displayName(avd), symbol: "play.fill") { start(avd) }
                    .help("Start the \(EmulatorLauncher.displayName(avd)) emulator")
            }
            if avds.count > Self.visibleAVDs {
                Menu("More Emulators") {
                    ForEach(avds.dropFirst(Self.visibleAVDs), id: \.self) { avd in
                        Button(EmulatorLauncher.displayName(avd)) { start(avd) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
            }
            restartLink
        }
        .task { await model.emulators?.reload() }  // AVDs created in Android Studio since launch
    }

    private static let visibleAVDs = 4

    /// Secondary action: small and quiet, under the main one.
    private var restartLink: some View {
        Button("Restart adb", action: restartADB)
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .help("Kill and restart the adb server. Fixes devices stuck offline.")
    }

    private func restartADB() {
        Task { await model.devices?.restartServer() }
    }

    private func start(_ avd: String) {
        model.emulators?.start(avd) { message in model.features.show(Toast(kind: .error, message: message)) }
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
