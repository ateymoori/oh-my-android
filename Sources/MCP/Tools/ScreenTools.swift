import Foundation

/// Seeing the screen: image, UI tree, screen-reader audit.
enum ScreenTools {
    static let all = [screenshot, getUI, accessibilityAudit]

    static let screenshot = Tool(
        name: "screenshot",
        title: "Screenshot",
        description: "Screenshot of the device screen. Scaled so 1 px = 1 dp, the same coordinates as get_ui and tap. Prefer get_ui to read text or find elements; use this to check visuals.",
        effect: .read,
        parameters: [
            .boolean("full_resolution", "Native pixels instead of dp scale. Costs about 6x more tokens."),
            .boolean("save", "Also save a full-resolution PNG in ~/Desktop/Android Captures and return its path."),
        ]
    ) { call in
        let context = try await call.device()
        async let density = context.shell("wm density")
        let png = try await context.adb.screenshot(context.device)
        var notes: [String] = []
        if try call.arguments.bool("save") == true {
            let url = try CaptureLocation.file("Screenshot", "png")
            try png.write(to: url)
            notes.append("Saved: \(url.path)")
        }
        let dpi = WindowManagerOutput.effectiveDensity(try await density).map(Double.init) ?? 160
        let full = try call.arguments.bool("full_resolution") == true
        let image = try ImageScaler.jpeg(fromPNG: png, scale: full ? 1 : 160 / dpi)
        notes.insert("\(image.width)x\(image.height) \(full ? "px, \(Int(dpi)) dpi" : "dp")", at: 0)
        return ToolResult(content: [.image(image.data, mimeType: "image/jpeg"), .text(notes.joined(separator: "\n"))])
    }

    static let getUI = Tool(
        name: "get_ui",
        title: "Get UI tree",
        description: """
        UI elements on screen, one per line: [ref] Class "text" desc="…" #resource_id @x,y WxH flags. \
        Sizes in dp. Flags: tap, long, checked/unchecked, scroll, selected, password, disabled. \
        Refs work in tap and swipe until the screen changes.
        """,
        effect: .read,
        parameters: [
            .string("query", "Only elements whose text, description or resource id contains this (case-insensitive)."),
            .boolean("interactive_only", "Only elements that take input: tappable, checkable, scrollable, text fields."),
            .number("wait_seconds", "With query: wait up to this long for a match to appear.", range: 0...30),
        ]
    ) { call in
        let context = try await call.device()
        let query = try call.arguments.string("query")?.trimmed
        let deadline = Date.now.addingTimeInterval(try call.arguments.double("wait_seconds", in: 0...30) ?? 0)
        async let foreground = try? context.foregroundPackage()
        while true {
            let hierarchy = try await call.freshHierarchy(context)
            let header = [UITreeText.screenSummary(hierarchy), await foreground.map { "app \($0)" }].compactMap { $0 }.joined(separator: ", ")
            guard let query, !query.isEmpty else {
                return .text(header + "\n" + UITreeText.tree(hierarchy, interactiveOnly: try call.arguments.bool("interactive_only") == true))
            }
            let found = UITreeText.matches(query, in: hierarchy)
            if !found.isEmpty {
                return .text(header + "\n" + found.prefix(UITreeText.maxLines).map { UITreeText.line($0, hierarchy) }.joined(separator: "\n"))
            }
            if Date.now >= deadline { return .text(header + "\nNo element matches \"\(query)\".") }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    static let accessibilityAudit = Tool(
        name: "accessibility_audit",
        title: "Accessibility audit",
        description: """
        TalkBack reading order and problems on the current screen: missing labels, touch targets under 48x48 dp, \
        unlabeled images. Each stop: order, what TalkBack says, [ref], frame in dp.
        """,
        effect: .read,
        parameters: [.boolean("issues_only", "Only stops with problems. Default true; false gives the full reading order.")]
    ) { call in
        let context = try await call.device()
        let hierarchy = try await call.freshHierarchy(context)
        let items = AccessibilityTraversal.items(in: hierarchy)
        let issues = items.filter(\.hasIssues)
        let issuesOnly = try call.arguments.bool("issues_only") ?? true
        var lines = ["\(items.count) TalkBack stops, \(issues.count) with problems."]
        for item in issuesOnly ? issues : items {
            lines.append("\(item.order). \(item.spoken.isEmpty ? "(silent)" : item.spoken) [\(item.node.id)] \(UITreeText.frame(item.node.bounds, hierarchy))")
            lines += item.issues.map { "   ! " + $0 }
        }
        if issuesOnly, !items.isEmpty { lines.append("Pass issues_only=false for the full reading order.") }
        return .text(lines.joined(separator: "\n"))
    }
}
