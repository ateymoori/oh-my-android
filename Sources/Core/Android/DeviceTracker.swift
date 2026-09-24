import Foundation

/// Emits a signal whenever the set of connected devices may have changed.
protocol DeviceTracking: Sendable {
    func events() -> AsyncStream<Void>
}

/// Push-based tracking through `adb track-devices`: adb keeps one connection open and writes a line
/// on every connect, disconnect, or state change. No polling, no periodic wake-ups.
final class ADBDeviceTracker: DeviceTracking, @unchecked Sendable {
    private let adb: URL
    private let lock = NSLock()
    private var process: Process?
    private var continuation: AsyncStream<Void>.Continuation?
    private var stopped = false

    init(adb: URL) {
        self.adb = adb
    }

    func events() -> AsyncStream<Void> {
        // A burst of changes (emulator boot) needs one re-read, not one per line: keep the newest signal only.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.withLock {
                self.continuation = continuation
                self.stopped = false
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
            launch()
        }
    }

    private func launch() {
        guard !lock.withLock({ stopped }) else { return }
        let process = Process()
        process.executableURL = adb
        process.arguments = ["track-devices"]
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.lock.withLock { self?.continuation }?.yield()
            }
        }
        process.terminationHandler = { [weak self] _ in
            // adb server restarted (e.g. Android Studio relaunched it): reconnect after a short pause.
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { self.launch() }
        }
        lock.withLock { self.process = process }
        try? process.run()
    }

    private func stop() {
        let process = lock.withLock {
            stopped = true
            continuation = nil
            return self.process
        }
        process?.terminate()
    }
}
