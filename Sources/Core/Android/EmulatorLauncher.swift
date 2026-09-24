import Foundation

/// Lists the SDK's emulators (AVDs) and starts one. The emulator runs as its own process and keeps
/// running when this app quits, as it would when started from Android Studio.
enum EmulatorLauncher {
    static func executable(_ sdk: AndroidSDK) -> URL { sdk.root.appending(path: "emulator/emulator") }

    /// AVD names, sorted. Empty when the emulator package is not installed.
    static func avds(_ sdk: AndroidSDK) async -> [String] {
        let emulator = executable(sdk)
        guard FileManager.default.isExecutableFile(atPath: emulator.path),
              let output = try? await ProcessShellRunner(timeout: .seconds(10)).run(emulator, arguments: ["-list-avds"]).stdout
        else { return [] }
        return output.split(whereSeparator: \.isNewline).map { String($0).trimmed }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.hasPrefix("WARNING") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Starts the AVD with its window. `exited` runs if the process ends, with its exit status.
    static func launch(_ avd: String, sdk: AndroidSDK, exited: @escaping @Sendable (Int32) -> Void) throws {
        let process = Process()
        process.executableURL = executable(sdk)
        process.arguments = ["-avd", avd]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { exited($0.terminationStatus) }
        try process.run()
    }

    /// "Pixel 8 API 35" for "Pixel_8_API_35".
    static func displayName(_ avd: String) -> String { avd.replacingOccurrences(of: "_", with: " ") }
}
