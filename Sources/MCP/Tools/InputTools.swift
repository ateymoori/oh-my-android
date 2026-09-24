import Foundation

/// Touch and keys. Positions are dp; the device's current density converts them to pixels.
enum InputTools {
    static let all = [tap, swipe, typeText, pressKey]

    static let tap = Tool(
        name: "tap",
        title: "Tap",
        description: "Tap an element by ref (from get_ui), by visible text, or at x,y in dp. Give one of the three.",
        effect: .control,
        parameters: [
            .integer("ref", "Element ref from the latest get_ui."),
            .string("text", "Visible text or content description; exact match wins over contains."),
            .number("x", "X in dp, with y."),
            .number("y", "Y in dp, with x."),
            .boolean("long_press", "Hold for 1 s instead of a short tap."),
        ]
    ) { call in
        let context = try await call.device()
        let target = try await call.point(context, allowText: true)
        let x = Int(target.hierarchy.pixels(target.point.x).rounded()), y = Int(target.hierarchy.pixels(target.point.y).rounded())
        let long = try call.arguments.bool("long_press") == true
        try await context.shell(long ? "input swipe \(x) \(y) \(x) \(y) 1000" : "input tap \(x) \(y)")
        return .text("\(long ? "Long-pressed" : "Tapped") \(target.label) at \(Int(target.point.x)),\(Int(target.point.y)) dp.")
    }

    static let swipe = Tool(
        name: "swipe",
        title: "Swipe",
        description: """
        Swipe (finger moves in direction): up scrolls down the page, left goes to the next page. \
        Starts at the center of ref, or at x,y in dp, or in the middle of the screen.
        """,
        effect: .control,
        parameters: [
            .string("direction", "Finger direction.", required: true, oneOf: ["up", "down", "left", "right"]),
            .integer("ref", "Swipe inside this element (for example a list) from the latest get_ui."),
            .number("x", "Start X in dp, with y."),
            .number("y", "Start Y in dp, with x."),
            .number("distance", "Length in dp. Default: 60% of the element or screen.", range: 1...5000),
            .integer("duration_ms", "Default 300. Longer is a slow drag.", range: 50...5000),
        ]
    ) { call in
        let context = try await call.device()
        let direction = try call.arguments.choice("direction", ["up", "down", "left", "right"]) ?? { throw ToolInputError("direction is required.") }()
        let start = try await call.point(context, allowText: false)
        let vertical = direction == "up" || direction == "down"
        let defaultDistance = (vertical ? start.area.height : start.area.width) * 0.6
        let distance: Double = try call.arguments.double("distance", in: 1...5000) ?? defaultDistance
        let sign: Double = direction == "up" || direction == "left" ? -1 : 1
        let delta = CGVector(dx: vertical ? 0 : sign * distance, dy: vertical ? sign * distance : 0)
        // From x,y the finger starts there; otherwise the gesture is centred on the element or screen.
        let from = start.explicit ? start.point : CGPoint(x: start.point.x - delta.dx / 2, y: start.point.y - delta.dy / 2)
        let to = CGPoint(x: from.x + delta.dx, y: from.y + delta.dy)
        let px = { (value: Double) in Int(start.hierarchy.pixels(value).rounded()) }
        let duration = try call.arguments.int("duration_ms", in: 50...5000) ?? 300
        try await context.shell("input swipe \(px(from.x)) \(px(from.y)) \(px(to.x)) \(px(to.y)) \(duration)")
        return .text("Swiped \(direction) \(Int(distance)) dp from \(Int(from.x)),\(Int(from.y)).")
    }

    static let typeText = Tool(
        name: "type_text",
        title: "Type text",
        description: "Type into the focused field (tap it first). ASCII only, an adb limit.",
        effect: .control,
        parameters: [
            .string("text", "Text to type.", required: true),
            .boolean("submit", "Press Enter after typing."),
        ]
    ) { call in
        let context = try await call.device()
        let text = try call.arguments.requiredString("text")
        guard text.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
            throw ToolInputError("adb can type ASCII only, on one line. Use submit for Enter.")
        }
        // `input text` reads %s as a space.
        try await context.shell("input text \(text.replacingOccurrences(of: " ", with: "%s").shellQuoted)")
        if try call.arguments.bool("submit") == true { try await context.shell("input keyevent 66") }
        return .text("Typed \(text.count) characters.")
    }

    /// Key names for the model, mapped to key codes or shell commands.
    private static let keys: KeyValuePairs<String, String> = [
        "back": "input keyevent 4",
        "home": "input keyevent 3",
        "recents": "input keyevent 187",
        "enter": "input keyevent 66",
        "delete": "input keyevent 67",
        "tab": "input keyevent 61",
        "escape": "input keyevent 111",
        "up": "input keyevent 19",
        "down": "input keyevent 20",
        "left": "input keyevent 21",
        "right": "input keyevent 22",
        "volume_up": "input keyevent 24",
        "volume_down": "input keyevent 25",
        "power": "input keyevent 26",
        "wakeup": "input keyevent 224",
        "notifications": "cmd statusbar expand-notifications",
        "quick_settings": "cmd statusbar expand-settings",
    ]

    static let pressKey = Tool(
        name: "press_key",
        title: "Press key",
        description: "Press a system key. escape also hides the keyboard; delete is backspace.",
        effect: .control,
        parameters: [
            .string("key", "Key.", required: true, oneOf: keys.map(\.key)),
            .integer("times", "Repeat count. Default 1.", range: 1...50),
        ]
    ) { call in
        let context = try await call.device()
        let key = try call.arguments.choice("key", keys.map(\.key)) ?? { throw ToolInputError("key is required.") }()
        let command = keys.first { $0.key == key }!.value
        let times = try call.arguments.int("times", in: 1...50) ?? 1
        try await context.shell(Array(repeating: command, count: times).joined(separator: "; "))
        return .text("Pressed \(key)\(times > 1 ? " \(times) times" : "").")
    }
}

/// Where a gesture lands, in dp.
private struct GestureTarget {
    let point: CGPoint
    /// Element or screen the gesture belongs to.
    let area: CGRect
    let label: String
    /// Given as x,y by the caller.
    let explicit: Bool
    let hierarchy: UIHierarchy
}

private extension ToolCall {
    /// Resolves `ref`, `text` or `x`/`y` to a point in dp. With none of them: the screen centre.
    func point(_ context: DeviceContext, allowText: Bool) async throws -> GestureTarget {
        if let ref = try arguments.int("ref") {
            let (node, hierarchy) = try await node(ref: ref, context)
            return target(node, hierarchy, label: UITreeText.line(node, hierarchy))
        }
        if allowText, let text = try arguments.string("text"), !text.isEmpty {
            let hierarchy = try await freshHierarchy(context)
            guard let match = UITreeText.target(text, in: hierarchy) else { throw AppError("No element shows \"\(text)\". Call get_ui to see the screen.") }
            let label = UITreeText.line(match.node, hierarchy) + (match.count > 1 ? " (first of \(match.count) matches)" : "")
            return target(match.node, hierarchy, label: label)
        }
        let hierarchy = try await screenHierarchy(context)
        let screen = CGRect(x: 0, y: 0, width: hierarchy.dp(hierarchy.screen.width), height: hierarchy.dp(hierarchy.screen.height))
        switch (try arguments.double("x"), try arguments.double("y")) {
        case let (x?, y?):
            return GestureTarget(point: CGPoint(x: x, y: y), area: screen, label: "point", explicit: true, hierarchy: hierarchy)
        case (nil, nil):
            guard !allowText else { throw ToolInputError("Give ref, text, or x and y.") }
            return GestureTarget(point: CGPoint(x: screen.midX, y: screen.midY), area: screen, label: "screen", explicit: false, hierarchy: hierarchy)
        default:
            throw ToolInputError("Give both x and y.")
        }
    }

    private func target(_ node: UINode, _ hierarchy: UIHierarchy, label: String) -> GestureTarget {
        let frame = CGRect(x: hierarchy.dp(node.bounds.minX), y: hierarchy.dp(node.bounds.minY),
                           width: hierarchy.dp(node.bounds.width), height: hierarchy.dp(node.bounds.height))
        return GestureTarget(point: CGPoint(x: frame.midX, y: frame.midY), area: frame, label: label, explicit: false, hierarchy: hierarchy)
    }

    /// Screen size and density. The cached tree is enough unless the display changed since; `wm` output
    /// is cheap, and its size is swapped when the screen is rotated.
    private func screenHierarchy(_ context: DeviceContext) async throws -> UIHierarchy {
        let output = try await context.shell("wm density; dumpsys input | grep -m1 SurfaceOrientation; wm size")
        guard let density = WindowManagerOutput.effectiveDensity(output).map(Double.init),
              var size = WindowManagerOutput.effectiveSize(output) else { throw AppError("Could not read the screen size.") }
        if let rotation = output.firstMatch(of: /SurfaceOrientation: (\d)/).flatMap({ Int($0.1) }), rotation % 2 == 1 {
            size = CGSize(width: size.height, height: size.width)
        }
        let root = UINode(id: -1, className: "", resourceID: "", text: "", contentDescription: "", bounds: CGRect(origin: .zero, size: size), flags: .init())
        return UIHierarchy(root: root, density: density)
    }
}
