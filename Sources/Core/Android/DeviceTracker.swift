import Foundation

/// Emits a signal whenever the set of connected devices may have changed.
protocol DeviceTracking: Sendable {
    func events() -> AsyncStream<Void>
    /// Ends the stream and closes the connection.
    func stop()
}

/// Push-based tracking through the adb server's `host:track-devices` service: one local socket the server
/// writes to on every connect, disconnect, or state change. No polling, and no child process that could
/// outlive the app: a crash or force quit closes the socket with the app.
final class ADBDeviceTracker: DeviceTracking, @unchecked Sendable {
    private let adb: URL
    private let port: UInt16
    private let lock = NSLock()
    private var connection: FileHandle?
    private var continuation: AsyncStream<Void>.Continuation?
    private var stopped = false
    private var retryDelay: TimeInterval = 2

    init(adb: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.adb = adb
        port = environment["ANDROID_ADB_SERVER_PORT"].flatMap(UInt16.init) ?? 5037
    }

    func events() -> AsyncStream<Void> {
        // A burst of changes (emulator boot) needs one re-read, not one per line: keep the newest signal only.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.withLock {
                self.continuation = continuation
                self.stopped = false
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
            connect()
        }
    }

    private func connect() {
        guard !lock.withLock({ stopped }) else { return }
        guard let handle = Self.openTrackingSocket(port: port) else { return retryLater() }
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                // adb server stopped (adb kill-server, Android Studio restart): start it again and reconnect.
                handle.readabilityHandler = nil
                retryLater()
            } else {
                lock.withLock { retryDelay = 2; return continuation }?.yield()
            }
        }
        lock.withLock { connection = handle }
    }

    /// Starts the adb server, then reconnects. Waits 2 s, doubling up to a minute while it keeps failing.
    private func retryLater() {
        let delay: TimeInterval? = lock.withLock {
            guard !stopped else { return nil }
            connection = nil
            defer { retryDelay = min(retryDelay * 2, 60) }
            return retryDelay
        }
        guard let delay else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !lock.withLock({ self.stopped }) else { return }
            // No pipes: the forked server would inherit them and the wait would never end.
            let server = Process()
            server.executableURL = adb
            server.arguments = ["start-server"]
            server.standardInput = FileHandle.nullDevice
            server.standardOutput = FileHandle.nullDevice
            server.standardError = FileHandle.nullDevice
            server.terminationHandler = { [weak self] _ in self?.connect() }
            do { try server.run() } catch { connect() }
        }
    }

    func stop() {
        let connection = lock.withLock {
            stopped = true
            continuation = nil
            defer { self.connection = nil }
            return self.connection
        }
        connection?.readabilityHandler = nil
        try? connection?.close()
    }

    /// Connected socket with the track-devices request sent, or nil when the server does not answer.
    private static func openTrackingSocket(port: UInt16) -> FileHandle? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        // adb protocol: 4 hex digits of length, then the service name.
        let service = "host:track-devices"
        let request = Array((String(format: "%04x", service.utf8.count) + service).utf8)
        guard connected == 0, write(fd, request, request.count) == request.count else {
            close(fd)
            return nil
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
