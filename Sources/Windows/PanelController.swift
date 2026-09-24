import AppKit
import SwiftUI

/// Owns the floating panel and keeps it docked to the selected emulator's window.
/// Window positions of other apps cannot be observed without the Accessibility permission, so docking
/// uses a low-rate timer — but only while an emulator process exists and the panel is visible.
@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: AppModel
    private let tracker = EmulatorWindowTracker()
    private var dockTimer: Timer?
    /// Lives for the whole app session, so observers are never removed.
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        let hosting = NSHostingView(rootView: PanelRootView().environment(model))
        hosting.sizingOptions = []
        panel = FloatingPanel(contentView: hosting, size: Theme.panelSize)
        placeInitially()
        observeEmulatorProcesses()
        observePinning()
    }

    // MARK: - Pinning

    private func observePinning() {
        withObservationTracking {
            panel.setPinned(model.isPinned)
            updateDockTimer()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePinning() }
        }
    }

    func show() {
        panel.orderFrontRegardless()
        updateDockTimer()
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        updateDockTimer()
    }

    // MARK: - Docking

    private var emulatorIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.executableURL?.lastPathComponent.hasPrefix("qemu-system") == true
        }
    }

    private func observeEmulatorProcesses() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateDockTimer() }
            })
        }
        updateDockTimer()
    }

    private func updateDockTimer() {
        let shouldRun = model.isPinned && model.dockToEmulator && panel.isVisible && emulatorIsRunning
        if shouldRun, dockTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.dockIfNeeded() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            dockTimer = timer
            dockIfNeeded()
        } else if !shouldRun {
            dockTimer?.invalidate()
            dockTimer = nil
        }
    }

    private func dockIfNeeded() {
        guard model.isPinned, model.dockToEmulator else { return updateDockTimer() }
        guard let emulator = tracker.emulatorFrame(consolePort: model.devices?.selected?.consolePort) else { return }
        let gap: CGFloat = 12
        let visible = NSScreen.screens.first { $0.frame.intersects(emulator) }?.visibleFrame ?? emulator
        var x = emulator.minX - Theme.panelSize.width - gap
        if x < visible.minX { x = emulator.maxX + gap }  // no room on the left: dock on the right
        x = min(x, visible.maxX - Theme.panelSize.width)
        let y = max(emulator.maxY - Theme.panelSize.height, visible.minY)
        let origin = NSPoint(x: x, y: y)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func placeInitially() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - Theme.panelSize.width - 24, y: visible.midY - Theme.panelSize.height / 2))
    }
}
