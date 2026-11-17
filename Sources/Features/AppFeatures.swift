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
        try AppCommands.checkStart(output)
        return nil
    }
}

/// Package commands shared by the panel and the MCP server. Packages are already quoted or validated.
enum AppCommands {
    /// `pm reset-permissions` ignores `-p` and resets every app on the device. This revokes the runtime
    /// permissions of one app and clears "don't ask again", so the app asks again on next use. Grants
    /// the system gives by default or fixes stay, as after a fresh install.
    static func resetPermissions(_ package: String) -> String {
        "p=\(package); n=0; for perm in $(dumpsys package $p | sed -n '/runtime permissions:/,/^ *[A-Za-z ]*:$/p' "
            + "| grep -v -e GRANTED_BY_DEFAULT -e SYSTEM_FIXED -e POLICY_FIXED "
            + "| grep -o '^ *[A-Za-z0-9_.]*: granted=' | sed 's/: granted=//' | sort -u); do "
            + "pm revoke $p $perm 2>/dev/null; pm clear-permission-flags $p $perm user-set user-fixed 2>/dev/null; "
            + "n=$((n+1)); done; echo $n"
    }

    /// `am start` prints "Error: …" lines on failure. Matching "Error" anywhere would also match an
    /// activity name such as .ErrorReportActivity.
    static func checkStart(_ output: String) throws {
        let errors = output.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { $0.hasPrefix("Error") }
        if !errors.isEmpty { throw AppError(errors.joined(separator: "\n")) }
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
        // Copies the whole APK: minutes for a large one over USB or Wi-Fi.
        let output = try await context.adb.run(context.device, ["install", "-r", "-d", "-g", url.path], timeout: .seconds(600))
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
    /// Shell command for the package; quote the package with `shellQuoted`.
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
        command: { "pm clear \($0.shellQuoted)" }, message: { "Cleared data of \($0)" }
    )
    static let forceStop = ForegroundAppActionFeature(
        id: "app.forceStop", title: "Force stop", symbol: "xmark.octagon.fill",
        command: { "am force-stop \($0.shellQuoted)" }
    )
    static let restart = ForegroundAppActionFeature(
        id: "app.restart", title: "Restart", symbol: "arrow.clockwise",
        command: { "am force-stop \($0.shellQuoted) && monkey -p \($0.shellQuoted) -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1" }
    )
    static let appInfo = ForegroundAppActionFeature(
        id: "app.info", title: "App info", symbol: "info.circle.fill",
        command: { "am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:\($0.shellQuoted)" }
    )
    static let revokePermissions = ForegroundAppActionFeature(
        id: "app.revoke", title: "Permissions", symbol: "hand.raised.fill", isDestructive: true,
        command: { AppCommands.resetPermissions($0.shellQuoted) }, message: { "Permissions reset for \($0)" }
    )
    static let uninstall = ForegroundAppActionFeature(
        id: "app.uninstall", title: "Uninstall", symbol: "trash.slash.fill", isDestructive: true,
        command: { "pm uninstall \($0.shellQuoted)" }, message: { "Uninstalled \($0)" }
    )
}
