import Foundation

/// One stop in the screen-reader traversal.
struct AccessibilityItem: Identifiable, Hashable, Sendable {
    let order: Int
    let node: UINode
    let role: String
    /// What TalkBack would announce, approximately.
    let spoken: String
    let issues: [String]

    var id: Int { node.id }
    var hasIssues: Bool { !issues.isEmpty }
}

/// Approximates TalkBack's traversal: depth-first; an actionable node (clickable, focusable, checkable)
/// is one stop and swallows its children (their text is merged into the announcement); a non-actionable
/// node with text is a stop of its own; pure containers are skipped.
enum AccessibilityTraversal {
    static let minimumTargetDp = 48.0

    static func items(in hierarchy: UIHierarchy) -> [AccessibilityItem] {
        var items: [AccessibilityItem] = []
        visit(hierarchy.root, hierarchy: hierarchy, viewport: hierarchy.root.bounds, into: &items)
        return items
    }

    /// `viewport` is the nearest scrolling container: nodes cut by its edges are only partly on screen.
    private static func visit(_ node: UINode, hierarchy: UIHierarchy, viewport: CGRect, into items: inout [AccessibilityItem]) {
        guard node.bounds.width > 0, node.bounds.height > 0 else { return }
        let actionable = node.flags.clickable || node.flags.focusable || node.flags.checkable || node.flags.longClickable
        if actionable {
            items.append(item(for: node, mergedText: mergedText(node), hierarchy: hierarchy, viewport: viewport, order: items.count + 1))
            return
        }
        if !node.text.isEmpty || !node.contentDescription.isEmpty {
            items.append(item(for: node, mergedText: ownText(node), hierarchy: hierarchy, viewport: viewport, order: items.count + 1))
        }
        let inner = node.flags.scrollable ? node.bounds : viewport
        for child in spatiallyOrdered(node.children, hierarchy: hierarchy) { visit(child, hierarchy: hierarchy, viewport: inner, into: &items) }
    }

    /// TalkBack orders siblings by position: rows top to bottom, then left to right within a row.
    /// Two siblings share a row when their vertical centres are within half a row (16 dp).
    private static func spatiallyOrdered(_ nodes: [UINode], hierarchy: UIHierarchy) -> [UINode] {
        let rowTolerance = 16 * hierarchy.density / 160
        return nodes.sorted { a, b in
            if abs(a.bounds.midY - b.bounds.midY) > rowTolerance { return a.bounds.midY < b.bounds.midY }
            return a.bounds.minX < b.bounds.minX
        }
    }

    private static func item(for node: UINode, mergedText: String, hierarchy: UIHierarchy, viewport: CGRect, order: Int) -> AccessibilityItem {
        let role = role(of: node)
        var parts: [String] = []
        if !mergedText.isEmpty { parts.append(mergedText) }
        if node.flags.checkable { parts.append(node.flags.checked ? "checked" : "not checked") }
        if node.flags.selected { parts.append("selected") }
        if !node.flags.enabled { parts.append("disabled") }
        if !role.isEmpty, role != "Text" { parts.append(role) }
        if node.flags.clickable, node.flags.enabled { parts.append("double-tap to activate") }

        var issues: [String] = []
        let actionable = node.flags.clickable || node.flags.focusable || node.flags.checkable
        if actionable, mergedText.isEmpty { issues.append("No label: TalkBack says only \"\(role.isEmpty ? "unlabeled" : role)\"") }
        if node.flags.naf { issues.append("NAF: actionable without accessible text") }
        if role == "Image", node.contentDescription.isEmpty, node.text.isEmpty, !actionable { issues.append("Image without description (fine only if decorative)") }
        if node.flags.clickable {
            let w = hierarchy.dp(node.bounds.width), h = hierarchy.dp(node.bounds.height)
            // uiautomator clips bounds to the visible part: a row cut by the list edge only looks small.
            let r = node.bounds
            let cutVertically = r.minY <= viewport.minY || r.maxY >= viewport.maxY
            let cutHorizontally = r.minX <= viewport.minX || r.maxX >= viewport.maxX
            if (w < minimumTargetDp && !cutHorizontally) || (h < minimumTargetDp && !cutVertically) {
                issues.append("Touch target \(Int(w.rounded())) × \(Int(h.rounded())) dp, minimum 48 × 48")
            }
        }
        return AccessibilityItem(order: order, node: node, role: role, spoken: parts.joined(separator: ", "), issues: issues)
    }

    /// Text spoken for an actionable node: its own label, else the labels of its descendants in order.
    private static func mergedText(_ node: UINode) -> String {
        let own = ownText(node)
        if !own.isEmpty { return own }
        return node.children.map(mergedText).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func ownText(_ node: UINode) -> String {
        if node.flags.password { return "password field" }
        return node.contentDescription.isEmpty ? node.text : node.contentDescription
    }

    static func role(of node: UINode) -> String {
        let cls = node.shortClass
        switch true {
        case cls.contains("ImageButton"): return "Button"
        case cls.contains("Button"): return "Button"
        case cls.contains("EditText"), cls.contains("AutoComplete"): return "Edit field"
        case cls.contains("CheckBox"): return "Checkbox"
        case cls.contains("Switch"), cls.contains("ToggleButton"): return "Switch"
        case cls.contains("RadioButton"): return "Radio button"
        case cls.contains("SeekBar"), cls.contains("Slider"): return "Slider"
        case cls.contains("Spinner"): return "Dropdown"
        case cls.contains("ImageView"): return "Image"
        case cls.contains("TextView"): return node.flags.clickable ? "Button" : "Text"
        case cls.contains("RecyclerView"), cls.contains("ListView"), cls.contains("ScrollView"), cls.contains("ViewPager"): return "List"
        case cls.contains("WebView"): return "Web view"
        case cls.contains("Tab"): return "Tab"
        default:
            // Compose reports android.view.View for everything; infer from behaviour.
            if node.flags.checkable { return "Checkbox" }
            if node.flags.clickable { return "Button" }
            if node.flags.scrollable { return "List" }
            return node.text.isEmpty && node.contentDescription.isEmpty ? "" : "Text"
        }
    }
}
