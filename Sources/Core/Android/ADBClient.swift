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

    /// Runs several commands in one `adb shell` round-trip and returns the output of each, in order.
    /// Nil when the outputs cannot be told apart (the shell stopped early, an exotic OEM shell).
    func shell(_ device: Device, sections commands: [String]) async throws -> [String]? {
        let separator = "@@OHMYANDROID@@"
        let output = try await shell(device, commands.joined(separator: "; echo \(separator); "))
        let sections = output.components(separatedBy: separator)
        return sections.count == commands.count ? sections : nil
    }
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
        let listed = try await execute(["devices", "-l"])
            .split(whereSeparator: \.isNewline)
            .compactMap(Self.device(fromListLine:))
        // Boot state and AVD name cost one adb call each: read all devices at once.
        return await withTaskGroup(of: (Int, Device).self) { group in
            for (index, device) in listed.enumerated() {
                group.addTask { (index, await details(of: device)) }
            }
            var devices = listed
            for await (index, device) in group { devices[index] = device }
            return devices
        }
    }

    func shell(_ device: Device, _ command: String) async throws -> String {
        try await run(device, ["shell", command])
    }

    func console(_ device: Device, _ arguments: [String]) async throws -> String {
        let output = try await run(device, ["emu"] + arguments)
        if output.contains("KO:") { throw AppError(output.trimmed) }
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

    /// "emulator-5554  device product:sdk_gphone64 model:sdk_gphone64_arm64 device:emu64a transport_id:1".
    /// The header and adb's own notes ("* daemon started successfully") are not devices.
    private static func device(fromListLine line: Substring) -> Device? {
        guard !line.hasPrefix("List of devices"), !line.hasPrefix("*") else { return nil }
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        let model = parts.first { $0.hasPrefix("model:") }.map { $0.dropFirst("model:".count).replacingOccurrences(of: "_", with: " ") }
        return Device(serial: parts[0], model: model ?? parts[0], state: Device.State(rawValue: parts[1]) ?? .other)
    }

    private func details(of listed: Device) async -> Device {
        guard listed.isOnline else { return listed }
        async let booted = try? shell(listed, "getprop sys.boot_completed")
        async let avdName = avdName(of: listed)
        var device = listed
        device.isBooted = await booted?.trimmed == "1"
        device.avdName = await avdName
        return device
    }

    private func avdName(of device: Device) async -> String? {
        guard device.isEmulator else { return nil }
        let output = try? await console(device, ["avd", "name"])
        return output?.split(whereSeparator: \.isNewline).first.map { String($0).trimmed }
    }
}
