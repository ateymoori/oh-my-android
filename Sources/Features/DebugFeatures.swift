import Foundation

/// Sets the three animation scales to zero, the same switch Espresso and Maestro want.
struct AnimationsOffFeature: ToggleFeature, BatchReadable {
    let id = "debug.animationsOff"
    let title = "Animations"
    let symbol = "figure.walk.motion"
    let category = FeatureCategory.layout
    let help = "Turns all system animations off (window, transition, animator)."

    private let keys = ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]

    let read = DeviceRead(command: "settings get global animator_duration_scale") { .toggle($0.trimmed == "0") }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        for key in keys { try await context.putSetting("global", key, on ? "0" : "1") }
    }
}

/// Opens the Layout Inspector: a frozen screenshot with element bounds, sizes, paddings and gaps in dp.
struct LayoutInspectorFeature: ActionFeature {
    let id = "debug.inspect"
    let title = "Inspect"
    let symbol = "ruler.fill"
    let category = FeatureCategory.layout
    let help = "Measure the screen like Figma: hover for sizes, click and hover for distances, all in dp."

    func perform(_ context: DeviceContext) async throws -> String? {
        await context.host.openLayoutInspector(context, nil)
        return nil
    }
}

extension DebugPropertyToggleFeature {
    static let layoutBounds = DebugPropertyToggleFeature(id: "debug.layoutBounds", title: "Bounds", symbol: "rectangle.dashed", property: "debug.layout", onValue: "true")
    static let overdraw = DebugPropertyToggleFeature(id: "debug.overdraw", title: "Overdraw", symbol: "square.3.layers.3d", property: "debug.hwui.overdraw", onValue: "show")
    static let gpuBars = DebugPropertyToggleFeature(id: "debug.gpuBars", title: "GPU bars", symbol: "chart.bar.fill", property: "debug.hwui.profile", onValue: "visual_bars")
}

extension SettingToggleFeature {
    static let showTaps = SettingToggleFeature(id: "debug.showTaps", title: "Show taps", symbol: "hand.tap.fill", category: .layout, namespace: "system", key: "show_touches")
    static let pointerLocation = SettingToggleFeature(id: "debug.pointer", title: "Pointer", symbol: "scope", category: .layout, namespace: "system", key: "pointer_location")
}

/// Opens Developer options for everything the panel does not cover.
struct DeveloperOptionsFeature: ActionFeature {
    let id = "debug.devOptions"
    let title = "Dev options"
    let symbol = "wrench.and.screwdriver.fill"
    let category = FeatureCategory.layout

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS")
        return nil
    }
}
