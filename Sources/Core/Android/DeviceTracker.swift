import Foundation
import Synchronization

/// Emits a signal whenever the set of connected devices may have changed.
protocol DeviceTracking: Sendable {
    func events() -> AsyncStream<Void>
    /// Ends the stream and closes the connection.
    func stop()
}

/// Push-based tracking through the adb server's `host:track-devices` service: one local socket the server
/// writes to on every connect, disconnect, or state change. No polling, and no child process that could
/// outlive the app: a crash or force quit closes the socket with the app.
final class ADBDeviceTracker: DeviceTracking {
    private struct State {
        var connection: FileHandle?
        var continuation: AsyncStream<Void>.Continuation?
        var stopped = false
        var retryDelay = ADBDeviceTracker.firstRetryDelay
    }

    private static let firstRetryDelay: Duration = .seconds(2)
    private static let maxRetryDelay: Duration = .seconds(60)
    private let adb: URL
    private let port: UInt16
    private let state = Mutex(State())

    init(adb: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.adb = adb
        port = environment["ANDROID_ADB_SERVER_PORT"].flatMap(UInt16.init) ?? 5037
    }

    func events() -> AsyncStream<Void> {
        // A burst of changes (emulator boot) needs one re-read, not one per line: keep the newest signal only.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            state.withLock {
                $0.continuation = continuation
                $0.stopped = false
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
            connect()
        }
    }

    func stop() {
        let connection = state.withLock { state in
            state.stopped = true
            state.continuation = nil
            defer { state.connection = nil }
            return state.connection
        }
        connection?.readabilityHandler = nil
        try? connection?.close()
    }

    private var isStopped: Bool { state.withLock(\.stopped) }

    private func connect() {
        guard !isStopped else { return }
        guard let handle = Self.openTrackingSocket(port: port) else { return retryLater() }
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                // adb server stopped (adb kill-server, Android Studio restart): start it again and reconnect.
                handle.readabilityHandler = nil
                retryLater()
            } else {
                state.withLock { state in
                    state.retryDelay = Self.firstRetryDelay
                    return state.continuation
                }?.yield()
            }
        }
        state.withLock { $0.connection = handle }
    }

    /// Starts the adb server, then reconnects. Waits 2 s, doubling up to a minute while it keeps failing.
    private func retryLater() {
        let delay: Duration? = state.withLock { state in
            guard !state.stopped else { return nil }
            state.connection = nil
            defer { state.retryDelay = min(state.retryDelay * 2, Self.maxRetryDelay) }
            return state.retryDelay
        }
        guard let delay else { return }
        Task { [weak self, adb] in
            try? await Task.sleep(for: delay)
            guard self?.isStopped == false else { return }
            await ProcessShellRunner.runDetached(adb, arguments: ["start-server"])
            self?.connect()
        }
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
