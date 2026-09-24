import AppKit
import SwiftUI

/// Standard document-style window for the inspectors: unified glass toolbar, title + subtitle,
/// remembered frame. SwiftUI installs the `.toolbar` on first display and re-fits the window to the
/// content minimum while doing so; the default size is therefore applied right after the toolbar exists.
@MainActor
final class ToolWindow {
    let window: NSWindow
    private let defaultSize: NSSize
    private let autosaveName: String
    private var toolbarObservation: NSKeyValueObservation?

    init<Content: View>(title: String, defaultSize: NSSize, minSize: NSSize, content: Content) {
        self.defaultSize = defaultSize
        autosaveName = title
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = minSize
        window.title = title
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .managed]  // a tool window follows the user to the current Space
        window.center()
        toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] _, change in
            guard case .some(.some) = change.newValue else { return }
            Task { @MainActor in self?.applyInitialFrame() }
        }
    }

    func present(subtitle: String) {
        window.subtitle = subtitle
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Once: restore the remembered frame, or use the default size. Runs after the toolbar re-fit.
    private func applyInitialFrame() {
        toolbarObservation = nil
        DispatchQueue.main.async { [window, defaultSize, autosaveName] in
            if !window.setFrameUsingName(autosaveName) {
                window.setContentSize(defaultSize)
                window.center()
            }
            window.setFrameAutosaveName(autosaveName)
        }
    }
}
