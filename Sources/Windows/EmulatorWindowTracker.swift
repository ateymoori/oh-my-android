import AppKit
import CoreGraphics

/// Finds the on-screen frame of Google's emulator (device window plus toolbar) so the panel can dock beside it.
struct EmulatorWindowTracker {
    /// Union frame of one emulator's visible windows in AppKit coordinates.
    /// Prefers the emulator process started for `avdName` or on `consolePort`; falls back to the frontmost one.
    /// Matched by process arguments: window titles of other apps are hidden without Screen Recording access.
    func emulatorFrame(consolePort: Int?, avdName: String?) -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var framesByProcess: [Int: CGRect] = [:]
        var preferredProcess: Int?
        var order: [Int] = []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner.hasPrefix("qemu-system"),  // the emulator process; never other apps named after QEMU
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.height > 300
            else { continue }
            if framesByProcess[pid] == nil {
                order.append(pid)
                if preferredProcess == nil, Self.isEmulator(pid, avdName: avdName, consolePort: consolePort) { preferredProcess = pid }
            }
            framesByProcess[pid] = framesByProcess[pid].map { $0.union(bounds) } ?? bounds
        }
        guard let pid = preferredProcess ?? order.first, let frame = framesByProcess[pid] else { return nil }
        return Self.flip(frame)
    }

    /// `qemu-system… -avd Name` or `@Name`, `-port 5556`. Only reads processes of this user.
    private static func isEmulator(_ pid: Int, avdName: String?, consolePort: Int?) -> Bool {
        let arguments = processArguments(pid)
        for (index, argument) in arguments.enumerated() {
            let next = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            if let avdName, argument == "@\(avdName)" || (argument == "-avd" && next == avdName) { return true }
            if let consolePort, argument == "-port", next == String(consolePort) { return true }
        }
        return false
    }

    /// argv of a process from KERN_PROCARGS2: argc, the executable path, padding, then the arguments.
    private static func processArguments(_ pid: Int) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        let strings = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return Array(strings.dropFirst().prefix(argc))  // dropFirst: the executable path
    }

    /// CoreGraphics uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func flip(_ rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
