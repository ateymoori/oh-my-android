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
        DebugPropertyToggleFeature.layoutBounds,
        DebugPropertyToggleFeature.overdraw,
        DebugPropertyToggleFeature.gpuBars,
        SettingToggleFeature.showTaps,
        SettingToggleFeature.pointerLocation,
        AnimationsOffFeature(),
        DeveloperOptionsFeature(),

        // Accessibility
        TalkBackFeature(),
        BoldTextFeature(),
        ColorInversionFeature(),

        // Navigation & input
        KeyEventFeature.back,
        KeyEventFeature.home,
        KeyEventFeature.recents,
        TypeTextFeature(),
        KeyEventFeature.hideKeyboard,
        SettingToggleFeature.softKeyboard,

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
