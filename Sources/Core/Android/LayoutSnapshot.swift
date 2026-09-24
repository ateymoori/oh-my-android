import Foundation

/// One node of the accessibility/view hierarchy as reported by `uiautomator dump`. Bounds are pixels.
struct UINode: Identifiable, Hashable, Sendable {
    let id: Int
    let className: String
    let resourceID: String
    let text: String
    let contentDescription: String
    let bounds: CGRect
    let flags: Flags
    var children: [UINode] = []

    /// Accessibility-relevant attributes from the dump.
    struct Flags: Hashable, Sendable {
        var clickable = false
        var longClickable = false
        var focusable = false
        var enabled = true
        var checkable = false
        var checked = false
        var selected = false
        var scrollable = false
        var password = false
        /// uiautomator's own "not accessibility friendly" verdict: actionable but unlabeled.
        var naf = false
    }

    /// "TextView" instead of "android.widget.TextView".
    var shortClass: String { className.split(separator: ".").last.map(String.init) ?? className }
    /// "title" instead of "com.example.app:id/title".
    var shortResourceID: String { resourceID.split(separator: "/").last.map(String.init) ?? resourceID }
    var label: String {
        if !text.isEmpty { return "\"\(text)\"" }
        if !resourceID.isEmpty { return shortResourceID }
        if !contentDescription.isEmpty { return contentDescription }
        return shortClass
    }

    /// Identity is the id: nodes are compared on every pointer move, and synthesized conformance would
    /// hash and compare the whole subtree. Ids are unique within one snapshot.
    static func == (lhs: UINode, rhs: UINode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Deepest (smallest) node containing the point.
    func hitTest(_ point: CGPoint) -> UINode? {
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return nil }
        let inner = children.compactMap { $0.hitTest(point) }.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        return inner ?? self
    }
}

/// Screenshot plus hierarchy taken at the same moment, with the density needed to speak in dp.
struct LayoutSnapshot: Sendable {
    let image: Data
    let root: UINode
    let screen: CGSize
    let density: Double

    func dp(_ pixels: Double) -> Double { pixels * 160 / density }
}

protocol LayoutSnapshotReading: Sendable {
    func snapshot(on device: Device, adb: ADBClient) async throws -> LayoutSnapshot
}

struct UIAutomatorSnapshotReader: LayoutSnapshotReading {
    func snapshot(on device: Device, adb: ADBClient) async throws -> LayoutSnapshot {
        async let image = adb.execOut(device, "screencap -p")
        async let density = adb.shell(device, "wm density")
        let xml = try await dumpHierarchy(on: device, adb: adb)
        guard let root = HierarchyXMLParser.parse(xml) else { throw AppError("Could not read the view hierarchy.") }
        let dpi = WindowManagerOutput.effectiveDensity(try await density).map(Double.init) ?? 160
        return LayoutSnapshot(image: try await image, root: root, screen: root.bounds.size, density: dpi)
    }

    /// uiautomator refuses while the screen animates; one retry covers the usual case.
    private func dumpHierarchy(on device: Device, adb: ADBClient) async throws -> Data {
        // /data/local/tmp belongs to the shell user: not visible to apps or in the user's files, and removed after.
        let file = "/data/local/tmp/oyama_ui.xml"
        let command = "uiautomator dump \(file) >/dev/null 2>&1 && cat \(file); rm -f \(file)"
        for attempt in 0..<2 {
            let data = try await adb.execOut(device, command)
            if data.count > 100 { return data }
            if attempt == 0 { try await Task.sleep(for: .milliseconds(600)) }
        }
        throw AppError("uiautomator returned nothing. Wait for animations to finish and retry.")
    }
}

private final class HierarchyXMLParser: NSObject, XMLParserDelegate {
    private var stack: [UINode] = []
    private var root: UINode?
    private var nextID = 0

    static func parse(_ data: Data) -> UINode? {
        let delegate = HierarchyXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.root
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard element == "node" else { return }
        func flag(_ key: String) -> Bool { attributes[key] == "true" }
        let node = UINode(
            id: nextID,
            className: attributes["class"] ?? "",
            resourceID: attributes["resource-id"] ?? "",
            text: attributes["text"] ?? "",
            contentDescription: attributes["content-desc"] ?? "",
            bounds: Self.rect(attributes["bounds"] ?? ""),
            flags: UINode.Flags(
                clickable: flag("clickable"), longClickable: flag("long-clickable"), focusable: flag("focusable"),
                enabled: attributes["enabled"] != "false", checkable: flag("checkable"), checked: flag("checked"),
                selected: flag("selected"), scrollable: flag("scrollable"), password: flag("password"), naf: flag("NAF")
            )
        )
        nextID += 1
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        guard element == "node", let node = stack.popLast() else { return }
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }

    /// "[l,t][r,b]"
    private static func rect(_ text: String) -> CGRect {
        let numbers = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).compactMap { Double($0) }
        guard numbers.count == 4 else { return .zero }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }
}
