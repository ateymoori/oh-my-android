import Foundation

/// Single registration point. Order inside a block is display order (most used first, three per row).
enum FeatureCatalog {
    static let all: [any Feature] = [
        // Appearance
        DarkModeFeature(),
        FontScaleFeature(),
        DisplayScaleFeature(),
        DeviceLanguageFeature(),
        EmulatorFeatures.rotate,

        // App (acts on the app in the foreground)
        ForegroundAppActionFeature.restart,
        ForegroundAppActionFeature.clearData,
        DeepLinkFeature(),
        DataInspectorFeature(),
        InstallAPKFeature(),
        ForegroundAppActionFeature.appInfo,
        ForegroundAppActionFeature.revokePermissions,
        ForegroundAppActionFeature.forceStop,
        ForegroundAppActionFeature.uninstall,

        // Capture
        ScreenshotFeature(),
        ScreenRecordFeature(),
        RecordingQualityFeature(),
        RevealCapturesFeature(),

        // Network
        NetworkProfileFeature(),
        AirplaneModeFeature(),
        WifiFeature(),
        MobileDataFeature(),

        // Layout & performance
        LayoutInspectorFeature(),
        DebugPropertyToggleFeature(id: "debug.layoutBounds", title: "Bounds", symbol: "rectangle.dashed", property: "debug.layout", onValue: "true"),
        DebugPropertyToggleFeature(id: "debug.overdraw", title: "Overdraw", symbol: "square.3.layers.3d", property: "debug.hwui.overdraw", onValue: "show"),
        DebugPropertyToggleFeature(id: "debug.gpuBars", title: "GPU bars", symbol: "chart.bar.fill", property: "debug.hwui.profile", onValue: "visual_bars"),
        SettingToggleFeature(id: "debug.showTaps", title: "Show taps", symbol: "hand.tap.fill", category: .layout, namespace: "system", key: "show_touches"),
        SettingToggleFeature(id: "debug.pointer", title: "Pointer", symbol: "scope", category: .layout, namespace: "system", key: "pointer_location"),
        AnimationsOffFeature(),
        DeveloperOptionsFeature(),

        // Accessibility
        TalkBackFeature(),
        BoldTextFeature(),
        ColorInversionFeature(),

        // Navigation & input
        BackFeature(),
        HomeFeature(),
        RecentsFeature(),
        TypeTextFeature(),
        HideKeyboardFeature(),
        SettingToggleFeature(id: "input.softKeyboard", title: "Soft keys", symbol: "keyboard.fill", category: .navigation, namespace: "secure", key: "show_ime_with_hard_keyboard"),

        // Simulate (emulator only)
        LocationPresetFeature(),
        CustomLocationFeature(),
        BatteryLevelFeature(),
        ChargingFeature(),
        EmulatorFeatures.fingerprint,
        EmulatorFeatures.incomingCall,
        IncomingSMSFeature(),

        // Snapshots (emulator only)
        EmulatorFeatures.snapshotSave,
        EmulatorFeatures.snapshotLoad,
    ]

    struct Section: Identifiable {
        let category: FeatureCategory
        let features: [any Feature]
        var id: String { category.id }
    }

    static func sections(for device: Device) -> [Section] {
        FeatureCategory.allCases.compactMap { category in
            let features = all.filter { $0.category == category && $0.supports(device) }
            return features.isEmpty ? nil : Section(category: category, features: features)
        }
    }
}
