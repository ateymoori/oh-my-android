import Foundation

struct TalkBackFeature: ToggleFeature, BatchReadable {
    let id = "a11y.talkback"
    let title = "TalkBack"
    let symbol = "person.wave.2.fill"
    let category = FeatureCategory.accessibility
    let help = "Screen reader on/off. Swipe to navigate, double-tap to activate."

    private static let service = "com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService"

    let read = DeviceRead(command: "settings get secure enabled_accessibility_services") {
        .toggle($0.lowercased().contains("talkback"))
    }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        if on {
            try await context.putSetting("secure", "enabled_accessibility_services", Self.service)
            try await context.putSetting("secure", "accessibility_enabled", "1")
        } else {
            try await context.shell("settings delete secure enabled_accessibility_services")
            try await context.putSetting("secure", "accessibility_enabled", "0")
        }
    }
}

struct BoldTextFeature: ToggleFeature, BatchReadable {
    let id = "a11y.boldText"
    let title = "Bold text"
    let symbol = "bold"
    let category = FeatureCategory.accessibility

    let read = DeviceRead(command: "settings get secure font_weight_adjustment") { .toggle((Int($0.trimmed) ?? 0) > 0) }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.putSetting("secure", "font_weight_adjustment", on ? "300" : "0")
    }
}

struct ColorInversionFeature: ToggleFeature, BatchReadable {
    let id = "a11y.invert"
    let title = "Invert colors"
    let symbol = "circle.lefthalf.filled"
    let category = FeatureCategory.accessibility

    let read = DeviceRead(command: "settings get secure accessibility_display_inversion_enabled") { .toggle($0.trimmed == "1") }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.putSetting("secure", "accessibility_display_inversion_enabled", on ? "1" : "0")
    }
}
