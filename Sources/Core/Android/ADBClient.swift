import Foundation

/// Everything the app needs from Android Debug Bridge. Features depend on this protocol only.
protocol ADBClient: Sendable {
    func devices() async throws -> [Device]
    /// Runs a command in the device shell and returns stdout.
    @discardableResult func shell(_ device: Device, _ command: String) async throws -> String
    /// Sends an emulator console command (`adb emu …`). Emulators only.
    @discardableResult func console(_ device: Device, _ arguments: [String]) async throws -> String
    /// Runs a shell command and returns raw stdout bytes (for screenshots).
    func execOut(_ device: Device, _ command: String) async throws -> Data
    /// Runs any adb sub-command against the device.
    @discardableResult func run(_ device: Device, _ arguments: [String]) async throws -> String
    /// Kills and restarts the adb server — the manual fix for devices stuck offline.
    func restartServer() async throws
}

extension ADBClient {
    /// PNG of the screen. On devices with several displays (foldables) `screencap` prints a warning
    /// before the image on the same stream; everything before the PNG signature is dropped.
    func screenshot(_ device: Device) async throws -> Data {
        let data = try await execOut(device, "screencap -p")
        guard let start = data.firstRange(of: Data([0x89, 0x50, 0x4E, 0x47]))?.lowerBound else {
            throw AppError("screencap returned no image.")
        }
        return Data(data[start...])
    }
}

struct ConsoleError: LocalizedError {
    let output: String
    var errorDescription: String? { output.trimmed }
}

struct AndroidDebugBridge: ADBClient {
    let sdk: AndroidSDK
    let runner: ShellRunning

    /// Starts the adb server without pipes. A server spawned implicitly by a piped client would inherit
    /// the pipe and keep it open forever, which is the classic way adb scripts hang.
    func startServer() async {
        await ProcessShellRunner.runDetached(sdk.adb, arguments: ["start-server"])
    }

    func devices() async throws -> [Device] {
        let output = try await execute(["devices", "-l"])
        var devices: [Device] = []
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let serial = parts[0]
            let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? serial
            var device = Device(serial: serial, model: model, state: Device.State(rawValue: parts[1]) ?? .other)
            if device.isEmulator, device.isReady {
                device.avdName = try? await console(device, ["avd", "name"]).split(whereSeparator: \.isNewline).first.map(String.init)?.trimmed
            }
            devices.append(device)
        }
        return devices
    }

    func shell(_ device: Device, _ command: String) async throws -> String {
        try await run(device, ["shell", command])
    }

    func console(_ device: Device, _ arguments: [String]) async throws -> String {
        let output = try await run(device, ["emu"] + arguments)
        if output.contains("KO:") { throw ConsoleError(output: output) }
        return output
    }

    func execOut(_ device: Device, _ command: String) async throws -> Data {
        try await runner.runData(sdk.adb, arguments: ["-s", device.serial, "exec-out", command])
    }

    func run(_ device: Device, _ arguments: [String]) async throws -> String {
        try await execute(["-s", device.serial] + arguments)
    }

    func restartServer() async throws {
        _ = try? await runner.run(sdk.adb, arguments: ["kill-server"])
        try await Task.sleep(for: .milliseconds(500))
        await startServer()
    }

    private func execute(_ arguments: [String]) async throws -> String {
        let result = try await runner.run(sdk.adb, arguments: arguments)
        guard result.isSuccess else {
            throw ShellError(command: "adb " + arguments.joined(separator: " "), result: result)
        }
        return result.stdout
    }
}
