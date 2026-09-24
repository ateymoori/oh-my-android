import SwiftUI

struct ToastView: View {
    let toast: Toast?

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 6) {
                    Image(systemName: toast.kind == .error ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.kind == .error ? .red : .green)
                    Text(toast.message).font(.caption).lineLimit(3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toast)
        .padding(.horizontal, 12)
    }
}
