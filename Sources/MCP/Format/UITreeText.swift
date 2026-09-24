import Foundation

/// Compact text form of a UI tree, written for a model to read: one line per useful node, in dp.
///
///     [23] Button "Sign in" #sign_in @16,700 379x48 tap
///
/// `[23]` is the ref for `tap` and `swipe`, `#` the resource id (view id or Compose testTag), `@x,y` the
/// top-left corner and `WxH` the size, all in dp. Layout-only wrappers are left out and their children
/// move up, which removes most of the tree without losing anything a model acts on.
enum UITreeText {
    static let maxLines = 400
    static let maxText = 80

    static func tree(_ hierarchy: UIHierarchy, interactiveOnly: Bool) -> String {
        var lines: [String] = []
        var omitted = 0
        func visit(_ node: UINode, depth: Int) {
            guard isVisible(node, in: hierarchy) else { return }
            let shown = interactiveOnly ? isInteractive(node) : isUseful(node)
            if shown {
                if lines.count < maxLines {
                    lines.append(String(repeating: " ", count: interactiveOnly ? 0 : depth) + line(node, hierarchy))
                } else {
                    omitted += 1
                }
            }
            for child in node.children { visit(child, depth: shown ? depth + 1 : depth) }
        }
        visit(hierarchy.root, depth: 0)
        if lines.isEmpty { lines.append(interactiveOnly ? "No interactive elements on screen." : "Screen has no readable elements.") }
        if omitted > 0 { lines.append("… \(omitted) more. Narrow with query or interactive_only.") }
        return lines.joined(separator: "\n")
    }

    /// Nodes whose text, content description or resource id contains the query (case-insensitive).
    static func matches(_ query: String, in hierarchy: UIHierarchy) -> [UINode] {
        hierarchy.root.flattened.filter { node in
            isVisible(node, in: hierarchy)
                && [node.text, node.contentDescription, node.resourceID].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Best node for a text target: exact text or description first, then contains.
    static func target(_ text: String, in hierarchy: UIHierarchy) -> (node: UINode, count: Int)? {
        let candidates = matches(text, in: hierarchy)
        let exact = candidates.filter { $0.text.caseInsensitiveCompare(text) == .orderedSame || $0.contentDescription.caseInsensitiveCompare(text) == .orderedSame }
        let pool = exact.isEmpty ? candidates : exact
        return pool.first.map { ($0, pool.count) }
    }

    static func line(_ node: UINode, _ hierarchy: UIHierarchy) -> String {
        var parts = ["[\(node.id)]"]
        let kind = node.shortClass
        if !kind.isEmpty, kind != "View" { parts.append(kind) }
        if !node.text.isEmpty { parts.append(quoted(node.text)) }
        if !node.contentDescription.isEmpty, node.contentDescription != node.text { parts.append("desc=" + quoted(node.contentDescription)) }
        if !node.resourceID.isEmpty { parts.append("#" + node.shortResourceID) }
        parts.append(frame(node.bounds, hierarchy))
        let flags = node.flags
        if flags.clickable { parts.append("tap") }
        if flags.longClickable { parts.append("long") }
        if flags.checkable { parts.append(flags.checked ? "checked" : "unchecked") }
        if flags.scrollable { parts.append("scroll") }
        if flags.selected { parts.append("selected") }
        if flags.password { parts.append("password") }
        if !flags.enabled { parts.append("disabled") }
        return parts.joined(separator: " ")
    }

    /// "@x,y WxH" in dp.
    static func frame(_ rect: CGRect, _ hierarchy: UIHierarchy) -> String {
        func dp(_ value: Double) -> Int { Int(hierarchy.dp(value).rounded()) }
        return "@\(dp(rect.minX)),\(dp(rect.minY)) \(dp(rect.width))x\(dp(rect.height))"
    }

    static func screenSummary(_ hierarchy: UIHierarchy) -> String {
        let width = Int(hierarchy.dp(hierarchy.screen.width).rounded()), height = Int(hierarchy.dp(hierarchy.screen.height).rounded())
        return "Screen \(width)x\(height) dp, \(Int(hierarchy.density)) dpi"
    }

    static func quoted(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let short = flat.count > maxText ? String(flat.prefix(maxText)) + "…" : flat
        return "\"" + short.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func isVisible(_ node: UINode, in hierarchy: UIHierarchy) -> Bool {
        node.bounds.width > 0 && node.bounds.height > 0 && node.bounds.intersects(CGRect(origin: .zero, size: hierarchy.screen))
    }

    private static func isInteractive(_ node: UINode) -> Bool {
        node.flags.clickable || node.flags.longClickable || node.flags.checkable || node.flags.scrollable || isTextField(node)
    }

    private static func isUseful(_ node: UINode) -> Bool {
        isInteractive(node) || !node.text.isEmpty || !node.contentDescription.isEmpty || !node.resourceID.isEmpty
    }

    private static func isTextField(_ node: UINode) -> Bool {
        node.className.hasSuffix("EditText") || node.className.hasSuffix("AutoCompleteTextView")
    }
}
