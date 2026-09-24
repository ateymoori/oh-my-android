import Foundation

/// Everything the server offers, in a fixed order (stable lists let clients cache and models reuse prompts).
enum Catalog {
    static let tools: [Tool] = {
        let groups: [[Tool]] = [DeviceTools.all, ScreenTools.all, InputTools.all, AppTools.all, DataTools.all, EmulatorTools.all]
        return groups.flatMap { $0 }
    }()

    static let instructions = """
    Oh My Android drives Android emulators and phones over adb. All positions and sizes are dp, like layout code; \
    screenshots are scaled to 1 px = 1 dp. Work in a loop: get_ui (cheap text) or screenshot → act (tap, type_text, \
    swipe, press_key) → get_ui to check. Refs from get_ui stay valid until the screen changes. \
    With several devices, pass device (see list_devices). Data tools need a debuggable build.
    """

    static let prompts: [Prompt] = [
        Prompt(
            name: "accessibility_review",
            title: "Accessibility review",
            description: "Audit the current screen with TalkBack order, labels and touch targets, then propose code fixes.",
            text: """
            Review the accessibility of the screen now shown on the Android device.
            1. Call accessibility_audit with issues_only=false and take a screenshot.
            2. For each problem, find the view or composable in this codebase (use the resource id or text) and propose a fix: \
            contentDescription or semantics label, 48x48 dp touch targets (minimumInteractiveComponentSize), merged semantics, \
            decorative images with null descriptions.
            3. Check that the reading order makes sense and point out steps that are out of order.
            4. Call set_device_settings with font_scale=2, check the screen for clipped or overlapping text with get_ui and a \
            screenshot, then restore font_scale to its first value.
            Report a short table: problem, element, fix, file.
            """
        ),
        Prompt(
            name: "ui_matrix",
            title: "UI test matrix",
            description: "Check the current screen in dark mode, large fonts, display size, RTL and pseudo-locales, then restore.",
            text: """
            Test the screen now shown on the Android device under stress settings.
            1. Call get_device_state and remember the settings so you can restore them.
            2. For each case, call set_device_settings, then screenshot, and get_ui when the image is unclear:
               dark_mode=true; font_scale=1.3; font_scale=2; display_scale=1.35; locale=ar-EG (RTL); locale=en-XA (long text).
               Reset the previous case before the next one.
            3. Look for clipped or truncated text, overlap, wrong colors or contrast in dark mode, mirrored layout errors in RTL, \
            hard-coded strings that did not change with the locale.
            4. Restore all settings to their first values.
            Report each problem with the case, the element, and a proposed code fix.
            """
        ),
        Prompt(
            name: "debug_crash",
            title: "Debug crash",
            description: "Find the latest crash in logcat, map the stack trace to code, and propose a fix.",
            arguments: [PromptArgument(name: "package", description: "App package. Default: the app on screen.")],
            text: """
            Find and fix the latest crash of the Android app{package}.
            1. Call logcat with crash=true and lines=200. If it is empty, call logcat{packageArgument} with level=E.
            2. Find the root cause in the stack trace (the last "Caused by") and the first frame in this app's code.
            3. Open that code in this codebase and explain why it fails.
            4. Propose a fix. When the steps to reproduce are clear, reproduce with open_app (restart=true) and the input tools, \
            and confirm the fix after the user rebuilds.
            """
        ),
    ]
}

struct Prompt: Sendable {
    let name: String
    let title: String
    let description: String
    var arguments: [PromptArgument] = []
    /// Message text. `{package}` and `{packageArgument}` are filled from the arguments.
    let text: String

    var definition: JSONValue {
        var result: [String: JSONValue] = ["name": .string(name), "title": .string(title), "description": .string(description)]
        if !arguments.isEmpty {
            result["arguments"] = .array(arguments.map { ["name": .string($0.name), "description": .string($0.description), "required": .bool($0.required)] })
        }
        return .object(result)
    }

    func messages(_ values: [String: String]) -> JSONValue {
        let package = values["package"]?.trimmed ?? ""
        let body = text
            .replacingOccurrences(of: "{package}", with: package.isEmpty ? "" : " \(package)")
            .replacingOccurrences(of: "{packageArgument}", with: package.isEmpty ? "" : " package=\(package)")
        return [["role": "user", "content": ["type": "text", "text": .string(body)]]]
    }
}

struct PromptArgument: Sendable {
    let name: String
    let description: String
    var required = false
}
