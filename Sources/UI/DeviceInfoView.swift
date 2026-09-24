import SwiftUI

/// One-line device summary that expands to the details a tester needs.
struct DeviceInfoView: View {
    @Environment(AppModel.self) private var model

    private var store: DeviceInfoStore { model.deviceInfo }

    var body: some View {
        if let info = store.info(for: model.devices?.selected) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { store.isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(info.summary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(store.isExpanded ? 90 : 0))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if store.isExpanded {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        row("Play Services", info.hasPlayServices ? (info.playServicesVersion ?? "installed") : "not installed")
                        row("ABI", info.abi)
                        row("Display", info.display)
                        row("RAM", info.memory)
                        row("Storage", info.storage)
                    }
                    .font(.caption2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Device details")
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
    }
}
