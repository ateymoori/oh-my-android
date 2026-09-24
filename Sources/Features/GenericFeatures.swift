import Foundation

/// Toggle backed by `settings put <namespace> <key> 1|0`.
struct SettingToggleFeature: ToggleFeature, BatchReadable {
    let id: String
    let title: String
    let symbol: String
    let category: FeatureCategory
    let namespace: String
    let key: String

    var read: DeviceRead {
        DeviceRead(command: "settings get \(namespace) \(key)") { .toggle($0.trimmed == "1") }
    }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.putSetting(namespace, key, on ? "1" : "0")
    }
}

/// Toggle backed by a `debug.*` system property, applied live through the activity manager.
struct DebugPropertyToggleFeature: ToggleFeature, BatchReadable {
    let id: String
    let title: String
    let symbol: String
    let property: String
    let onValue: String
    let category: FeatureCategory = .layout

    var read: DeviceRead {
        DeviceRead(command: "getprop \(property)") { [onValue] in .toggle($0.trimmed == onValue) }
    }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.setDebugProperty(property, on ? onValue : "false")
    }
}

/// Emulator console command with fixed arguments.
struct ConsoleActionFeature: ActionFeature {
    let id: String
    let title: String
    let symbol: String
    let category: FeatureCategory
    let arguments: [String]
    var message: String? = nil
    let requiresEmulator = true

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.adb.console(context.device, arguments)
        return message
    }
}
