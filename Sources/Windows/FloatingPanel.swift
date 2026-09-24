import AppKit

/// Borderless glass panel. Pinned: floats over everything on every Space without stealing focus.
/// Unpinned: an ordinary window that stays on its Space and activates the app when clicked.
final class FloatingPanel: NSPanel {
    init(contentView: NSView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        self.contentView = contentView
        setPinned(true)
    }

    func setPinned(_ pinned: Bool) {
        isFloatingPanel = pinned
        level = pinned ? .floating : .normal
        collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
        if pinned { styleMask.insert(.nonactivatingPanel) } else { styleMask.remove(.nonactivatingPanel) }
        if isVisible { orderFrontRegardless() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
