import AppKit
import SwiftUI

/// One reusable Layout Inspector window.
@MainActor
final class LayoutInspectorWindowController {
    private let store: LayoutInspectorStore
    private lazy var tool = ToolWindow(title: "Layout Inspector", defaultSize: NSSize(width: 560, height: 980), minSize: NSSize(width: 460, height: 640), content: LayoutInspectorView(store: store))

    init(store: LayoutInspectorStore) {
        self.store = store
    }

    func show(context: DeviceContext, overlay: URL? = nil) {
        tool.present(subtitle: context.device.displayName)
        if let overlay { store.loadOverlay(overlay) }
        Task { await store.open(context) }
    }
}
