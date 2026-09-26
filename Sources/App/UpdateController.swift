import AppKit
import Observation
import Sparkle

/// In-app updates through Sparkle. Checks at most once a day (one small HTTPS request for the release feed;
/// Sparkle schedules it, nothing polls) and never interrupts: a found update shows as a dot on the menu bar
/// icon and an "Update to …" menu item. Updates install only when the user chooses, and only when signed
/// with the EdDSA key in Info.plist and the same Developer ID as the running app.
@MainActor
@Observable
final class UpdateController: NSObject {
    /// Version of a found update the user has not looked at yet.
    private(set) var pendingVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Shows Sparkle's window: the pending update, or the result of a new check.
    func checkForUpdates() {
        NSApp.activate()  // a menu bar app is not active; the window would open behind
        controller?.checkForUpdates(nil)
    }
}

// Gentle reminders: https://sparkle-project.org/documentation/gentle-reminders
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks never open a window; the dot and menu item wait for the user.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { pendingVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}

/// Menu bar icon, with an orange dot while an update waits.
enum MenuBarIcon {
    static func image(badged: Bool) -> NSImage {
        guard let icon = NSImage(named: "MenuBarIcon") else { return NSImage() }
        guard badged else { return icon }
        let size = icon.size
        // Not a template (the dot has color), so the glyph takes the menu bar's text color at draw time.
        let image = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
            // Cut a gap around the dot so it reads as a badge over the glyph.
            NSColor.clear.set()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemOrange.set()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.accessibilityDescription = "Oh My Android, update available"
        return image
    }
}
