import AppKit
import CoreGraphics

/// Finds the on-screen frame of Google's emulator (device window plus toolbar) so the panel can dock beside it.
struct EmulatorWindowTracker {
    /// Union frame of one emulator's visible windows in AppKit coordinates.
    /// Prefers the emulator whose window title carries `consolePort` (e.g. "…:5556"); falls back to the first one.
    func emulatorFrame(consolePort: Int?) -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var framesByProcess: [Int: CGRect] = [:]
        var preferredProcess: Int?
        var order: [Int] = []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner.lowercased().contains("qemu"),
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.height > 300
            else { continue }
            if framesByProcess[pid] == nil { order.append(pid) }
            framesByProcess[pid] = framesByProcess[pid].map { $0.union(bounds) } ?? bounds
            if let port = consolePort, let name = window[kCGWindowName as String] as? String, name.hasSuffix(":\(port)") {
                preferredProcess = pid
            }
        }
        guard let pid = preferredProcess ?? order.first, let frame = framesByProcess[pid] else { return nil }
        return Self.flip(frame)
    }

    /// CoreGraphics uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func flip(_ rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
