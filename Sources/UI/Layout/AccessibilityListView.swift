import SwiftUI

/// Screen-reader stops in traversal order, with role, announcement, and audit findings.
struct AccessibilityListView: View {
    @Bindable var store: LayoutInspectorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TalkBack order").font(.headline)
                Spacer()
                let issues = store.accessibilityItems.filter(\.hasIssues).count
                Text(issues == 0 ? "no findings" : "\(issues) finding\(issues == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(issues == 0 ? .green : .orange)
            }
            .padding(10)
            Text("Approximate: derived from the accessibility node tree, same rules TalkBack uses for merging.")
                .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.bottom, 6)
            Divider()
            ScrollViewReader { proxy in
                List(store.accessibilityItems, selection: selection) { item in
                    row(item).tag(item.node).id(item.id)
                }
                .listStyle(.plain)
                .onChange(of: store.selected) { _, node in
                    if let node, store.accessibilityItem(for: node) != nil { proxy.scrollTo(node.id, anchor: .center) }
                }
            }
        }
        .frame(width: 300)
    }

    private var selection: Binding<UINode?> {
        Binding(get: { store.selected }, set: { store.selected = $0 })
    }

    private func row(_ item: AccessibilityItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(item.order)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(item.hasIssues ? Color.orange : Color.green))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !item.role.isEmpty { Text(item.role).font(.caption.weight(.semibold)) }
                    Text(item.node.shortResourceID.isEmpty ? item.node.shortClass : item.node.shortResourceID)
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Text(item.spoken.isEmpty ? "— nothing announced —" : "“\(item.spoken)”")
                    .font(.caption).foregroundStyle(item.spoken.isEmpty ? .orange : .primary).lineLimit(2)
                ForEach(item.issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.order). \(item.role). \(item.spoken.isEmpty ? "nothing announced" : item.spoken). \(item.issues.joined(separator: ". "))")
        .onHover { inside in if inside { store.hovered = item.node } }
    }
}
