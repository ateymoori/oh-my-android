import Foundation

/// Everything the server offers, in a fixed order (stable lists let clients cache and models reuse prompts).
enum Catalog {
    static let tools: [Tool] = {
        let groups: [[Tool]] = [DeviceTools.all, ScreenTools.all, InputTools.all, AppTools.all, DataTools.all, EmulatorTools.all]
        return groups.flatMap { $0 }
    }()

    static let instructions = """
    Oh My Android drives Android emulators and phones over adb. All positions and sizes are dp, like layout code; \
    screenshots are scaled to 1 px = 1 dp. get_ui is cheap text; a screenshot costs more tokens and shows visuals. \
    Input tools (tap, type_text, swipe, press_key) return a confirmation, not the new screen. \
    Refs from get_ui stay valid until the screen changes. \
    With several devices, pass device (see list_devices). Data tools need a debuggable build.
    """

    static let prompts: [Prompt] = [
        Prompt(
            name: "accessibility_review",
            title: "Accessibility review",
            description: "Audit the current screen with TalkBack order, labels and touch targets, then propose code fixes.",
            text: """
            Review the accessibility of the screen now shown on the Android device and propose code fixes in this codebase \
            (the resource id or text finds the view or composable). Cover TalkBack reading order, missing labels \
            (contentDescription or semantics), touch targets under 48x48 dp (minimumInteractiveComponentSize), merged \
            semantics, and decorative images that need a null description. Also check the screen at font_scale=2 for \
            clipped or overlapping text, then set font_scale back to its first value.
            Report a short table: problem, element, fix, file.
            """
        ),
        Prompt(
            name: "ui_matrix",
            title: "UI test matrix",
            description: "Check the current screen in dark mode, large fonts, display size, RTL and pseudo-locales, then restore.",
            text: """
            Test the screen now shown on the Android device under stress settings, one case at a time with the previous \
            case reset: dark_mode=true; font_scale=1.3; font_scale=2; display_scale=1.35; locale=ar-EG (RTL); \
            locale=en-XA (long text).
            Look for clipped or truncated text, overlap, wrong colors or contrast in dark mode, mirrored layout errors in RTL, \
            and hard-coded strings that did not change with the locale.
            The device must end with the settings it started with: read them with get_device_state before the first change \
            and restore them after the last case.
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
            The crash buffer (logcat crash=true lines=200) has the stack trace; if it is empty, try logcat{packageArgument} \
            with level=E. The root cause is usually the last "Caused by", and the first frame in this app's code shows where \
            to look. Explain why that code fails and propose a fix. When the steps to reproduce are clear, reproduce the crash \
            with open_app (restart=true) and the input tools, and confirm the fix after the user rebuilds.
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
