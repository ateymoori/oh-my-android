import Foundation

/// Facts about a device that matter while testing an app.
struct DeviceInfo: Equatable, Sendable {
    var androidVersion = ""
    var apiLevel = ""
    var hasPlayServices = false
    var playServicesVersion: String?
    var abi = ""
    var display = ""
    var memory = ""
    var storage = ""

    var summary: String {
        var parts = ["Android \(androidVersion)", "API \(apiLevel)"]
        parts.append(hasPlayServices ? "Play" : "No Play")
        return parts.joined(separator: " · ")
    }
}

protocol DeviceInfoReading: Sendable {
    func info(on device: Device, adb: ADBClient) async throws -> DeviceInfo
}

/// Collects everything in a single `adb shell` round-trip.
struct DeviceInfoReader: DeviceInfoReading {
    private static let separator = "@@"
    private static let script = [
        "getprop ro.build.version.release",
        "getprop ro.build.version.sdk",
        "pm list packages com.google.android.gms",
        "dumpsys package com.google.android.gms 2>/dev/null | grep -m1 versionName",
        "getprop ro.product.cpu.abi",
        "wm size",
        "wm density",
        "grep -E 'MemTotal|MemAvailable' /proc/meminfo",
        "df -k /data | tail -1",
    ].joined(separator: "; echo \(separator); ")

    func info(on device: Device, adb: ADBClient) async throws -> DeviceInfo {
        let sections = try await adb.shell(device, Self.script)
            .components(separatedBy: Self.separator)
            .map { $0.trimmed }
        guard sections.count == 9 else { throw AppError("Unexpected device output.") }

        var info = DeviceInfo()
        info.androidVersion = sections[0]
        info.apiLevel = sections[1]
        info.hasPlayServices = sections[2].contains("com.google.android.gms")
        info.playServicesVersion = sections[3].firstMatch(of: /versionName=([\d.]+)/).map { String($0.1) }
        info.abi = sections[4]
        info.display = Self.display(size: sections[5], density: sections[6])
        info.memory = Self.memory(sections[7])
        info.storage = Self.storage(sections[8])
        return info
    }

    private static func display(size: String, density: String) -> String {
        let resolution = WindowManagerOutput.effectiveSize(size).map { "\(Int($0.width))×\(Int($0.height))" } ?? "?"
        let dpi = WindowManagerOutput.effectiveDensity(density).map(String.init) ?? "?"
        return "\(resolution) · \(dpi) dpi"
    }

    private static func memory(_ text: String) -> String {
        let total = text.firstMatch(of: /MemTotal:\s+(\d+)/).flatMap { Double($0.1) } ?? 0
        let available = text.firstMatch(of: /MemAvailable:\s+(\d+)/).flatMap { Double($0.1) } ?? 0
        guard total > 0 else { return "?" }
        return "\(gigabytes(kilobytes: total - available)) of \(gigabytes(kilobytes: total)) GB used"
    }

    private static func storage(_ line: String) -> String {
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 4, let size = Double(columns[1]), let available = Double(columns[3]) else { return "?" }
        return "\(gigabytes(kilobytes: available)) of \(gigabytes(kilobytes: size)) GB free"
    }

    private static func gigabytes(kilobytes: Double) -> String {
        String(format: "%.1f", kilobytes / 1_048_576)
    }
}
