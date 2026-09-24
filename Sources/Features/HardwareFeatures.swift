import Foundation

struct BatteryLevelFeature: ChoiceFeature {
    let id = "hardware.battery"
    let title = "Battery"
    let symbol = "battery.50percent"
    let category = FeatureCategory.simulate
    let requiresEmulator = true
    let options: [FeatureOption] = ["100", "80", "50", "20", "15", "5", "1"].map { .init(id: $0, title: "\($0) %") }

    func selection(_ context: DeviceContext) async throws -> String? {
        let output = try await context.console("power", "display")
        return output.firstMatch(of: /capacity: (\d+)/).map { String($0.1) }
    }

    func select(_ optionID: String, _ context: DeviceContext) async throws {
        try await context.console("power", "capacity", optionID)
    }
}

struct ChargingFeature: ToggleFeature {
    let id = "hardware.charging"
    let title = "Charging"
    let symbol = "bolt.fill"
    let category = FeatureCategory.simulate
    let requiresEmulator = true

    func isOn(_ context: DeviceContext) async throws -> Bool {
        try await context.console("power", "display").contains("AC: online")
    }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.console("power", "ac", on ? "on" : "off")
        try await context.console("power", "status", on ? "charging" : "discharging")
    }
}

struct IncomingSMSFeature: TextActionFeature {
    let id = "hardware.sms"
    let title = "SMS"
    let symbol = "message.fill"
    let category = FeatureCategory.simulate
    let requiresEmulator = true
    let placeholder = "Message text, e.g. code 123456"

    func perform(_ text: String, _ context: DeviceContext) async throws -> String? {
        try await context.console("sms", "send", "5551234567", text)
        return nil
    }
}
