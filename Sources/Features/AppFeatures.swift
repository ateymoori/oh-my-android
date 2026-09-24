import Foundation

struct DeepLinkFeature: TextActionFeature {
    let id = "app.deepLink"
    let title = "Deep link"
    let symbol = "link"
    let category = FeatureCategory.app
    let placeholder = "myapp://path or https://…"
    let submitTitle = "Open"

    func perform(_ text: String, _ context: DeviceContext) async throws -> String? {
        let url = text.trimmed
        guard !url.isEmpty else { throw AppError("Enter a URL.") }
        let output = try await context.shell("am start -W -a android.intent.action.VIEW -d \(url.shellQuoted)")
        if output.contains("Error") { throw AppError(output.trimmed) }
        return nil
    }
}

/// Opens the read-only Data Inspector (SharedPreferences, SQLite) for debuggable apps.
struct DataInspectorFeature: ActionFeature {
    let id = "app.data"
    let title = "Data"
    let symbol = "cylinder.split.1x2.fill"
    let category = FeatureCategory.app
    let help = "Browse SharedPreferences and SQLite databases of debuggable apps. Read-only."

    func perform(_ context: DeviceContext) async throws -> String? {
        await context.host.openDataInspector(context)
        return nil
    }
}

struct InstallAPKFeature: ActionFeature {
    let id = "app.install"
    let title = "Install APK"
    let symbol = "shippingbox.fill"
    let category = FeatureCategory.app
    let help = "Pick an APK, or drop one on the panel."

    func perform(_ context: DeviceContext) async throws -> String? {
        guard let url = await context.host.chooseFile("apk", "Choose an APK to install on \(context.device.displayName)") else { return nil }
        return try await APKInstaller.install(url, context)
    }
}

enum APKInstaller {
    static func install(_ url: URL, _ context: DeviceContext) async throws -> String {
        let output = try await context.adb.run(context.device, ["install", "-r", "-d", "-g", url.path])
        guard output.contains("Success") else { throw AppError(output.trimmed) }
        return "Installed \(url.lastPathComponent)"
    }
}

/// Acts on whatever app is currently in the foreground.
struct ForegroundAppActionFeature: ActionFeature {
    let id: String
    let title: String
    let symbol: String
    let category: FeatureCategory = .app
    var isDestructive = false
    let command: @Sendable (String) -> String
    var message: (@Sendable (String) -> String)? = nil

    func perform(_ context: DeviceContext) async throws -> String? {
        let package = try await context.foregroundPackage()
        try await context.shell(command(package))
        return message?(package)
    }
}

extension ForegroundAppActionFeature {
    static let clearData = ForegroundAppActionFeature(
        id: "app.clearData", title: "Clear data", symbol: "trash.fill", isDestructive: true,
        command: { "pm clear \($0)" }, message: { "Cleared data of \($0)" }
    )
    static let forceStop = ForegroundAppActionFeature(
        id: "app.forceStop", title: "Force stop", symbol: "xmark.octagon.fill",
        command: { "am force-stop \($0)" }
    )
    static let restart = ForegroundAppActionFeature(
        id: "app.restart", title: "Restart", symbol: "arrow.clockwise",
        command: { "am force-stop \($0) && monkey -p \($0) -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1" }
    )
    static let appInfo = ForegroundAppActionFeature(
        id: "app.info", title: "App info", symbol: "info.circle.fill",
        command: { "am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:\($0)" }
    )
    static let revokePermissions = ForegroundAppActionFeature(
        id: "app.revoke", title: "Permissions", symbol: "hand.raised.fill", isDestructive: true,
        command: { "pm reset-permissions -p \($0)" }, message: { "Permissions reset for \($0)" }
    )
    static let uninstall = ForegroundAppActionFeature(
        id: "app.uninstall", title: "Uninstall", symbol: "trash.slash.fill", isDestructive: true,
        command: { "pm uninstall \($0)" }, message: { "Uninstalled \($0)" }
    )
}
