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
