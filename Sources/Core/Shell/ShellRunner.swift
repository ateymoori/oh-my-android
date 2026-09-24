import Foundation

/// Result of one finished process.
struct ShellResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var isSuccess: Bool { exitCode == 0 }
}

/// Error raised when a process exits with a non-zero status.
struct ShellError: LocalizedError {
    let command: String
    let result: ShellResult

    var errorDescription: String? {
        let message = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmed
        return message.isEmpty ? "\(command) failed (exit \(result.exitCode))" : message
    }
}

/// Abstraction over process execution so services stay testable and swappable.
protocol ShellRunning: Sendable {
    func run(_ executable: URL, arguments: [String]) async throws -> ShellResult
    func runData(_ executable: URL, arguments: [String]) async throws -> Data
}

/// Runs executables with `Process` without blocking any thread: pipes drain through readability
/// handlers and completion arrives through the termination handler.
struct ProcessShellRunner: ShellRunning {
    /// Upper bound for one command. adb answers in milliseconds; anything longer is a hung server.
    var timeout: Duration = .seconds(60)

    func run(_ executable: URL, arguments: [String]) async throws -> ShellResult {
        let output = try await launch(executable, arguments: arguments)
        return ShellResult(
            stdout: String(decoding: output.stdout, as: UTF8.self),
            stderr: String(decoding: output.stderr, as: UTF8.self),
            exitCode: output.status
        )
    }

    func runData(_ executable: URL, arguments: [String]) async throws -> Data {
        let output = try await launch(executable, arguments: arguments)
        guard output.status == 0 else {
            throw ShellError(
                command: executable.lastPathComponent + " " + arguments.joined(separator: " "),
                result: ShellResult(stdout: "", stderr: String(decoding: output.stderr, as: UTF8.self), exitCode: output.status)
            )
        }
        return output.stdout
    }

    /// Runs a process with no pipes and waits for it to exit. For `adb start-server`: the client returns
    /// once the daemon is up, and the daemon cannot inherit (and hold open) a pipe of ours.
    static func runDetached(_ executable: URL, arguments: [String]) async {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }
    }

    private struct Output: Sendable { let stdout: Data; let stderr: Data; let status: Int32 }

    private func launch(_ executable: URL, arguments: [String]) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = PipeCollector()
        let stderr = PipeCollector()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe

        let watchdog = Task.detached(priority: .background) { [timeout] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled, process.isRunning { process.terminate() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                watchdog.cancel()
                continuation.resume(returning: Output(stdout: stdout.finish(), stderr: stderr.finish(), status: finished.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                watchdog.cancel()
                process.terminationHandler = nil
                _ = stdout.finish()
                _ = stderr.finish()
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Accumulates everything written to a pipe as it arrives, so large outputs never stall the child.
/// Reads and the final drain run on one serial queue, so they can never race each other.
private final class PipeCollector: @unchecked Sendable {
    let pipe = Pipe()
    private var data = Data()
    private let queue = DispatchQueue(label: "PipeCollector")
    private let descriptor: Int32
    private let source: DispatchSourceRead

    init() {
        descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [pipe] in try? pipe.fileHandleForReading.close() }
        source.activate()
    }

    /// Takes what is left without blocking: a grandchild (adb's server daemon) may still hold the write end.
    func finish() -> Data {
        queue.sync {
            drain()
            source.cancel()
            return data
        }
    }

    /// Reads until the pipe is empty (EAGAIN) or closed (EOF). Runs on `queue` only.
    private func drain() {
        guard !source.isCancelled else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else {
                if count == 0 { source.cancel() }
                return
            }
            data.append(buffer, count: count)
        }
    }
}
