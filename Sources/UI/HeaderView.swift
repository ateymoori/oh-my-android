import SwiftUI

/// Device picker plus the pin toggle. Everything else was noise for daily use.
struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            devicePicker
            Button {
                withAnimation(.snappy(duration: 0.2)) { model.isPinned.toggle() }
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin.slash")
                    .foregroundStyle(model.isPinned ? Theme.accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Theme.headerControlHeight, height: Theme.headerControlHeight)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(model.isPinned ? "Unpin panel" : "Pin panel")
            .help(model.isPinned ? "Pinned: floats over all windows on every Space. Click to unpin." : "Unpinned: normal window on this Space. Click to pin.")
        }
    }

    private var devicePicker: some View {
        Menu {
            if model.devices?.devices.isEmpty ?? true {
                Text("No devices connected")
            }
            ForEach(model.devices?.devices ?? []) { device in
                Button {
                    model.devices?.selected = device
                } label: {
                    Label(device.problem.map { "\(device.displayName) — \($0)" } ?? device.displayName, systemImage: device.symbol)
                }
                .disabled(!device.isReady)
            }
            if let emulators = model.emulators, !emulators.avds.isEmpty {
                Divider()
                Menu("Start Emulator") {
                    ForEach(emulators.avds, id: \.self) { avd in
                        Button(EmulatorLauncher.displayName(avd)) {
                            emulators.start(avd) { message in model.features.show(Toast(kind: .error, message: message)) }
                        }
                    }
                }
                .disabled(emulators.starting != nil)
            }
            Divider()
            Button("Restart adb") { Task { await model.devices?.restartServer() } }
                .help("Kill and restart the adb server. Fixes devices stuck offline.")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.devices?.selected?.symbol ?? "iphone.slash")
                Text(headerTitle).lineLimit(1).truncationMode(.middle)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(model.devices?.selected == nil ? .secondary : .primary)
            .frame(height: Theme.headerControlHeight)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Target device")
        .accessibilityLabel("Device: \(headerTitle)")
    }

    /// Selected device, else a device that is not ready yet (the content explains why), else none.
    private var headerTitle: String {
        (model.devices?.selected ?? model.devices?.devices.first)?.displayName ?? "No Device"
    }
}
