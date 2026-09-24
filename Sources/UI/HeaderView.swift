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
            }
            .buttonStyle(.glass)
            .accessibilityLabel(model.isPinned ? "Unpin panel" : "Pin panel")
            .help(model.isPinned ? "Pinned: floats over all windows on every Space. Click to unpin." : "Unpinned: normal window on this Space. Click to pin.")
        }
    }

    private var devicePicker: some View {
        Menu {
            ForEach(model.devices?.devices ?? []) { device in
                Button {
                    model.devices?.selected = device
                } label: {
                    Label(device.state.problem.map { "\(device.displayName) — \($0)" } ?? device.displayName, systemImage: device.symbol)
                }
                .disabled(!device.isReady)
            }
            Divider()
            Button("Restart adb") { Task { await model.devices?.restartServer() } }
                .help("Kill and restart the adb server. Fixes devices stuck offline.")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.devices?.selected?.symbol ?? "iphone.slash")
                Text(headerTitle).lineLimit(1)
            }
            .font(.callout.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Target device")
    }

    /// Selected device, or the reason nothing is selected.
    private var headerTitle: String {
        if let device = model.devices?.selected { return device.displayName }
        if let stuck = model.devices?.devices.first, let problem = stuck.state.problem { return "\(stuck.displayName) — \(problem)" }
        return "No device"
    }
}
