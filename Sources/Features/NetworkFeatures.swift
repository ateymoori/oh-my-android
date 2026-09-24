import Foundation

/// Emulated radio speed and latency, applied through the emulator console.
struct NetworkProfileFeature: ChoiceFeature {
    let id = "network.profile"
    let title = "Speed"
    let symbol = "gauge.with.dots.needle.33percent"
    let category = FeatureCategory.network
    let requiresEmulator = true
    let help = "Emulated bandwidth and latency for all traffic."

    private struct Profile { let id: String; let title: String; let downloadBits: Int; let delay: String }

    private let profiles: [Profile] = [
        .init(id: "full", title: "Full speed", downloadBits: 0, delay: "none"),
        .init(id: "lte", title: "LTE", downloadBits: 173_000_000, delay: "30:60"),
        .init(id: "hsdpa", title: "HSDPA", downloadBits: 14_400_000, delay: "80:150"),
        .init(id: "umts", title: "3G", downloadBits: 1_920_000, delay: "umts"),
        .init(id: "edge", title: "EDGE", downloadBits: 236_800, delay: "edge"),
        .init(id: "gprs", title: "GPRS", downloadBits: 80_000, delay: "gprs"),
        .init(id: "gsm", title: "GSM (worst)", downloadBits: 14_400, delay: "600:1200"),
    ]

    var options: [FeatureOption] { profiles.map { .init(id: $0.id, title: $0.title) } }

    func selection(_ context: DeviceContext) async throws -> String? {
        let status = try await context.console("network", "status")
        guard let bits = status.firstMatch(of: /download speed:\s+(\d+) bits/).flatMap({ Int($0.1) }) else { return nil }
        return profiles.first { $0.downloadBits == bits }?.id
    }

    func select(_ optionID: String, _ context: DeviceContext) async throws {
        guard let profile = profiles.first(where: { $0.id == optionID }) else { return }
        try await context.console("network", "speed", profile.id)
        try await context.console("network", "delay", profile.delay)
    }
}

struct AirplaneModeFeature: ToggleFeature, BatchReadable {
    let id = "network.airplane"
    let title = "Offline"
    let symbol = "airplane"
    let category = FeatureCategory.network
    let help = "Airplane mode: no network at all."

    let read = DeviceRead(command: "cmd connectivity airplane-mode") { .toggle($0.trimmed == "enabled") }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.shell("cmd connectivity airplane-mode \(on ? "enable" : "disable")")
    }
}

struct WifiFeature: ToggleFeature, BatchReadable {
    let id = "network.wifi"
    let title = "Wi‑Fi"
    let symbol = "wifi"
    let category = FeatureCategory.network

    let read = DeviceRead(command: "settings get global wifi_on") { .toggle($0.trimmed != "0") }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.shell("svc wifi \(on ? "enable" : "disable")")
    }
}

struct MobileDataFeature: ToggleFeature, BatchReadable {
    let id = "network.mobileData"
    let title = "Mobile data"
    let symbol = "antenna.radiowaves.left.and.right"
    let category = FeatureCategory.network

    let read = DeviceRead(command: "settings get global mobile_data") { .toggle($0.trimmed != "0") }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.shell("svc data \(on ? "enable" : "disable")")
    }
}
