import SwiftUI

/// The panel's one layout for "nothing to control yet": icon or spinner, title, short explanation,
/// and actions. Sized for the narrow panel; the system ContentUnavailableView is made for full windows.
struct PanelMessage<Actions: View>: View {
    let symbol: String?
    let title: String
    let message: String
    var detail: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(tint)
                        .frame(height: 34)
                        .accessibilityHidden(true)
                } else {
                    ProgressView().controlSize(.regular).frame(height: 34)
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 6) { actions }
                .controlSize(.regular)
        }
        .frame(maxWidth: Theme.messageWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension PanelMessage where Actions == EmptyView {
    init(symbol: String?, title: String, message: String, detail: String? = nil, tint: Color = .secondary) {
        self.init(symbol: symbol, title: title, message: message, detail: detail, tint: tint) { EmptyView() }
    }
}

/// Full-width primary action inside a PanelMessage.
struct PanelMessageButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }
}
