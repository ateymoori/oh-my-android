import Foundation

/// Apps: list, launch, manage, install, logs.
enum AppTools {
    static let all = [listApps, openApp, manageApp, installAPK, logcat]

    static let listApps = Tool(
        name: "list_apps",
        title: "List apps",
        description: "Installed third-party apps. Marks the one on screen and debuggable ones (data tools need debuggable).",
        effect: .read,
        parameters: [.string("filter", "Only packages that contain this.")]
    ) { call in
        let context = try await call.device()
        async let foreground = try? context.foregroundPackage()
        let script = "for p in $(pm list packages -3 | cut -d: -f2); do if run-as $p true >/dev/null 2>&1; then echo \"$p debuggable\"; else echo $p; fi; done"
        let filter = try call.arguments.string("filter")?.trimmed ?? ""
        let current = await foreground
        let lines = try await context.shell(script).split(whereSeparator: \.isNewline)
            .map { $0.split(separator: " ").map(String.init) }
            .filter { !$0.isEmpty && (filter.isEmpty || $0[0].localizedCaseInsensitiveContains(filter)) }
            .sorted { $0[0] < $1[0] }
            .map { parts in
                let marks = Array(parts.dropFirst()) + (parts[0] == current ? ["on screen"] : [])
                return marks.isEmpty ? parts[0] : "\(parts[0]) (\(marks.joined(separator: ", ")))"
            }
        return .text(lines.isEmpty ? "No matching apps." : lines.joined(separator: "\n"))
    }

    static let openApp = Tool(
        name: "open_app",
        title: "Open app or link",
        description: "Launch an app and report its start time, or open a deep link / URL. Give package or url.",
        effect: .control,
        parameters: [
            .string("package", "App to launch."),
            .string("url", "Deep link or URL, e.g. myapp://orders/42."),
            .boolean("restart", "Force-stop first for a cold start."),
        ]
    ) { call in
        let context = try await call.device()
        if let url = try call.arguments.string("url"), !url.isEmpty {
            let package = call.arguments.has("package") ? " -p " + (try await call.package(context)) : ""
            let output = try await context.shell("am start -W -a android.intent.action.VIEW -d \(url.shellQuoted)\(package)")
            if output.contains("Error") { throw AppError(output.trimmed) }
            return .text("Opened \(url). " + launchSummary(output))
        }
        guard call.arguments.has("package") else { throw ToolInputError("Give package or url.") }
        let package = try await call.package(context)
        if try call.arguments.bool("restart") == true { try await context.shell("am force-stop \(package)") }
        let activity = try await context.shell("cmd package resolve-activity --brief -c android.intent.category.LAUNCHER \(package) | tail -n 1").trimmed
        guard activity.contains("/") else { throw AppError("\(package) has no launcher activity, or is not installed.") }
        let output = try await context.shell("am start -W -n \(activity.shellQuoted)")
        if output.contains("Error") { throw AppError(output.trimmed) }
        return .text("Launched \(activity). " + launchSummary(output))
    }

    /// "COLD start, 523 ms" from `am start -W`.
    private static func launchSummary(_ output: String) -> String {
        if output.contains("Activity not started") || output.contains("LaunchState: UNKNOWN") {
            return "It was already running and came to the front; pass restart=true for a cold start."
        }
        let state = output.firstMatch(of: /LaunchState: (\w+)/).map { "\($0.1) start" }
        let time = output.firstMatch(of: /TotalTime: (\d+)/).map { "\($0.1) ms" }
        let parts = [state, time].compactMap { $0 }
        return parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
    }

    private static let manageActions = ["force_stop", "clear_data", "reset_permissions", "grant_permission", "revoke_permission", "uninstall"]

    static let manageApp = Tool(
        name: "manage_app",
        title: "Manage app",
        description: "Force-stop, clear data, reset/grant/revoke permissions, or uninstall. Default: the app on screen.",
        effect: .destructive,
        parameters: [
            .string("action", "What to do.", required: true, oneOf: manageActions),
            .string("package", "Target app. Default: the app on screen."),
            .string("permission", "For grant/revoke, e.g. android.permission.CAMERA."),
        ]
    ) { call in
        let context = try await call.device()
        let action = try call.arguments.choice("action", manageActions) ?? { throw ToolInputError("action is required.") }()
        let package = try await call.package(context)
        let command: String
        switch action {
        case "force_stop": command = "am force-stop \(package)"
        case "clear_data": command = "pm clear \(package)"
        case "reset_permissions": command = "pm reset-permissions -p \(package)"
        case "uninstall": command = "pm uninstall \(package)"
        default:
            let permission = try call.arguments.requiredString("permission")
            guard permission.wholeMatch(of: /[A-Za-z0-9_.]+/) != nil else { throw ToolInputError("permission must look like android.permission.CAMERA.") }
            command = "pm \(action == "grant_permission" ? "grant" : "revoke") \(package) \(permission)"
        }
        let output = try await context.shell(command + " 2>&1").trimmed
        if output.localizedCaseInsensitiveContains("fail") || output.contains("Exception") { throw AppError(output) }
        return .text("\(action) \(package): \(output.isEmpty ? "done" : output)")
    }

    static let installAPK = Tool(
        name: "install_apk",
        title: "Install APK",
        description: "Install or update an APK from this Mac. Keeps data, allows downgrade, grants runtime permissions.",
        effect: .destructive,
        parameters: [.string("path", "Absolute path of the .apk on this Mac.", required: true)]
    ) { call in
        let context = try await call.device()
        let url = URL(filePath: (try call.arguments.requiredString("path") as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "apk", FileManager.default.isReadableFile(atPath: url.path) else {
            throw ToolInputError("No readable .apk at \(url.path).")
        }
        return .text(try await APKInstaller.install(url, context))
    }

    private static let levels = ["V", "D", "I", "W", "E", "F"]

    static let logcat = Tool(
        name: "logcat",
        title: "Read logcat",
        description: "Recent log lines as Level/Tag: message. Filter by app, level, text. crash=true reads the crash buffer (stack traces).",
        effect: .read,
        parameters: [
            .string("package", "Only this app's process; it must be running. Ignored with crash=true."),
            .string("level", "Minimum level. Default W.", oneOf: levels),
            .string("grep", "Only lines that match this regex (case-insensitive)."),
            .integer("since_seconds", "Only the last N seconds.", range: 1...86400),
            .integer("lines", "Most recent lines to return. Default 100.", range: 1...1000),
            .boolean("crash", "Crash buffer instead of the main log."),
        ]
    ) { call in
        let context = try await call.device()
        let arguments = call.arguments
        let crash = try arguments.bool("crash") == true
        var options = ["-d", "-v", "tag"]
        if crash { options += ["-b", "crash"] }
        if let seconds = try arguments.int("since_seconds", in: 1...86400) { options.append("-T \"$(( $(date +%s) - \(seconds) )).000\"") }
        var script = ""
        var filter = ""
        if arguments.has("package"), !crash {
            let package = try await call.package(context)
            script = "P=$(pidof -s \(package)); [ -z \"$P\" ] && echo '@@NOT_RUNNING' && exit 0; "
            options.append("--pid=$P")
        }
        let level = try arguments.choice("level", levels) ?? "W"
        if let pattern = try arguments.string("grep"), !pattern.isEmpty { filter += " | grep -iE -- \(pattern.shellQuoted)" }
        let count = try arguments.int("lines", in: 1...1000) ?? 100
        script += "logcat \(options.joined(separator: " ")) '*:\(level)'\(filter) | tail -n \(count)"
        let output = try await context.shell(script)
        if output.contains("@@NOT_RUNNING") { return .text("The app is not running. Launch it with open_app, or pass crash=true for crashes.") }
        let lines = output.split(whereSeparator: \.isNewline).map { $0.count > 500 ? $0.prefix(500) + "…" : String($0) }
        return .text(lines.isEmpty ? "No log lines match." : lines.joined(separator: "\n"))
    }
}
