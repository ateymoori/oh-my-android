import Foundation

struct DarkModeFeature: ToggleFeature, BatchReadable {
    let id = "display.darkMode"
    let title = "Dark mode"
    let symbol = "moon.fill"
    let category = FeatureCategory.appearance

    let read = DeviceRead(command: "cmd uimode night") { .toggle($0.contains("yes")) }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        try await context.shell("cmd uimode night \(on ? "yes" : "no")")
    }
}

struct FontScaleFeature: StepperFeature, BatchReadable {
    let id = "display.fontScale"
    let title = "Font size"
    let symbol = "textformat.size"
    let category = FeatureCategory.appearance
    let steps: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5, 1.8, 2.0]

    let read = DeviceRead(command: "settings get system font_scale") { .number(Double($0.trimmed) ?? 1.0) }

    func setValue(_ value: Double, _ context: DeviceContext) async throws {
        try await context.putSetting("system", "font_scale", String(format: "%.2f", value))
    }

    func label(for value: Double) -> String { String(format: "%.2f×", value) }
}

/// Scales the logical density (dp size) relative to the physical density.
struct DisplayScaleFeature: StepperFeature, BatchReadable {
    let id = "display.scale"
    let title = "Display size"
    let symbol = "arrow.up.left.and.arrow.down.right"
    let category = FeatureCategory.appearance
    let steps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5]

    var read: DeviceRead {
        DeviceRead(command: "wm density") { [steps] output in
            let density = WindowManagerOutput.density(output)
            guard let override = density.override, let physical = density.physical else { return .number(1.0) }
            let ratio = Double(override) / Double(physical)
            return .number(steps.min { abs($0 - ratio) < abs($1 - ratio) } ?? 1.0)
        }
    }

    func setValue(_ value: Double, _ context: DeviceContext) async throws {
        if value == 1.0 {
            try await context.shell("wm density reset")
        } else {
            guard let physical = WindowManagerOutput.density(try await context.shell("wm density")).physical else {
                throw AppError("Could not read the display density.")
            }
            try await context.shell("wm density \(Int((Double(physical) * value).rounded()))")
        }
    }

    func label(for value: Double) -> String { String(format: "%.0f%%", value * 100) }
}

struct DeviceLanguageFeature: ChoiceFeature, BatchReadable {
    let id = "display.language"
    let title = "Language"
    let symbol = "globe"
    let category = FeatureCategory.appearance
    let help = "Changes the device language instantly, no reboot."
    let options: [FeatureOption] = [
        .init(id: "en-US", title: "English (US)"),
        .init(id: "en-GB", title: "English (UK)"),
        .init(id: "sv-SE", title: "Svenska"),
        .init(id: "de-DE", title: "Deutsch"),
        .init(id: "fr-FR", title: "Français"),
        .init(id: "es-ES", title: "Español"),
        .init(id: "ar-EG", title: "العربية (RTL)"),
        .init(id: "fa-IR", title: "فارسی (RTL)"),
        .init(id: "ja-JP", title: "日本語"),
        .init(id: "zh-CN", title: "中文"),
        .init(id: "en-XA", title: "Pseudo-locale (long text)"),
        .init(id: "ar-XB", title: "Pseudo-locale (RTL)"),
    ]

    /// New Android answers `cmd locale`; older images fall back to the persisted property.
    let read = DeviceRead(
        command: "L=$(cmd locale get-device-locale 2>/dev/null); case \"$L\" in ''|*rror*) getprop persist.sys.locale;; *) echo \"$L\";; esac"
    ) { output in
        let locale = output.trimmed
        return .choice(locale.isEmpty ? nil : locale)
    }

    func select(_ optionID: String, _ context: DeviceContext) async throws {
        do {
            try await context.shell("cmd locale set-device-locale \(optionID)")
        } catch {
            // Older images: shell holds CHANGE_CONFIGURATION, so update-config applies immediately.
            try await context.shell("am update-config --locale \(optionID)")
        }
    }
}
