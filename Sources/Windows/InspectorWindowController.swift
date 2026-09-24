import AppKit
import SwiftUI

/// One reusable Data Inspector window.
@MainActor
final class InspectorWindowController {
    private let store: InspectorStore
    private lazy var tool = ToolWindow(title: "Data Inspector", defaultSize: NSSize(width: 980, height: 600), minSize: NSSize(width: 880, height: 440), content: InspectorView(store: store))

    init(store: InspectorStore) {
        self.store = store
    }

    func show(context: DeviceContext) {
        tool.present(subtitle: context.device.displayName)
        Task { await store.open(context) }
    }

    /// Deletes pulled database copies (private app data) from the temporary folder.
    func close() {
        store.discardLocalDatabases()
    }
}
