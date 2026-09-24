import Foundation

protocol ForegroundAppReading: Sendable {
    /// Package name of the app on screen, or nil when it cannot be determined.
    func package(on device: Device, adb: ADBClient) async throws -> String?
}

/// Reads the resumed activity from the activity manager. Called on demand, never polled.
struct ForegroundAppReader: ForegroundAppReading {
    func package(on device: Device, adb: ADBClient) async throws -> String? {
        let output = try await adb.shell(device, "dumpsys activity activities | grep -m1 -E 'Resumed:|ResumedActivity:'")
        guard let match = output.firstMatch(of: /u\d+ ([\w.]+)\//) else { return nil }
        return String(match.1)
    }
}
