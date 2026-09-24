import AppKit
import Observation

/// A design image laid over the screenshot for comparison.
struct DesignOverlay {
    enum Fit: String, CaseIterable, Identifiable {
        case fitWidth = "Fit width", x1 = "1×", x2 = "2×", x3 = "3×"
        var id: String { rawValue }
    }

    let image: NSImage
    var fit: Fit
    var opacity: Double = 0.5
    var difference = false
    /// Nudge in dp, applied after scaling.
    var offset = CGSize.zero

    /// Pixel size on the screenshot for the chosen fit.
    func pixelSize(for snapshot: LayoutSnapshot) -> CGSize {
        let scale: Double
        switch fit {
        case .fitWidth: scale = snapshot.screen.width / image.size.width
        case .x1: scale = snapshot.density / 160
        case .x2: scale = snapshot.density / 160 / 2
        case .x3: scale = snapshot.density / 160 / 3
        }
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// Picks 1×/2×/3× when the image width matches the screen width in dp at that export scale.
    static func detectFit(image: NSImage, snapshot: LayoutSnapshot) -> Fit {
        let screenDp = snapshot.dp(snapshot.screen.width)
        for (fit, factor) in [(Fit.x1, 1.0), (.x2, 2.0), (.x3, 3.0)] where abs(image.size.width / factor - screenDp) < 2 {
            return fit
        }
        return .fitWidth
    }
}

/// State of the Layout Inspector window: one frozen snapshot, hover and selection, grid, overlay.
@MainActor
@Observable
final class LayoutInspectorStore {
    private(set) var snapshot: LayoutSnapshot?
    /// Decoded once per capture; views must not decode the PNG in `body`, which runs on every pointer move.
    private(set) var screenImage: NSImage?
    private(set) var sampler: PixelSampler?
    private(set) var isLoading = false
    private(set) var error: String?
    var hovered: UINode?
    var hoveredPixel: CGPoint?
    var selected: UINode?
    var overlay: DesignOverlay?
    var showGrid: Bool = UserDefaults.standard.bool(forKey: LayoutInspectorStore.gridKey) {
        didSet { UserDefaults.standard.set(showGrid, forKey: Self.gridKey) }
    }
    var showAccessibility: Bool = UserDefaults.standard.bool(forKey: LayoutInspectorStore.a11yKey) {
        didSet { UserDefaults.standard.set(showAccessibility, forKey: Self.a11yKey) }
    }
    /// Screen-reader stops in traversal order, computed once per snapshot.
    private(set) var accessibilityItems: [AccessibilityItem] = []
    let gridStepDp: Double = 8

    private static let gridKey = "layout.grid"
    private static let a11yKey = "layout.a11y"
    private let reader: LayoutSnapshotReading
    private var context: DeviceContext?
    /// Design image chosen before the first snapshot arrived; applied once there is a screen to fit.
    private var pendingOverlay: URL?

    init(reader: LayoutSnapshotReading) {
        self.reader = reader
    }

    var hoveredColor: PixelColor? { hoveredPixel.flatMap { sampler?.color(at: $0) } }

    func open(_ context: DeviceContext) async {
        self.context = context
        await capture()
    }

    func capture() async {
        guard let context, !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let fresh = try await reader.snapshot(on: context.device, adb: context.adb)
            sampler = await Task.detached { PixelSampler(png: fresh.image) }.value
            screenImage = NSImage(data: fresh.image)
            snapshot = fresh
            accessibilityItems = AccessibilityTraversal.items(in: fresh.hierarchy)
            selected = nil
            hovered = nil
            if let pending = pendingOverlay { pendingOverlay = nil; loadOverlay(pending) }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func hover(at pixel: CGPoint?) {
        hoveredPixel = pixel
        let node = pixel.flatMap { snapshot?.root.hitTest($0) }
        if node != hovered { hovered = node }
    }

    func click(at pixel: CGPoint) {
        let node = snapshot?.root.hitTest(pixel)
        selected = node == selected ? nil : node
    }

    func loadOverlay(_ url: URL) {
        guard let snapshot else { pendingOverlay = url; return }
        guard let image = NSImage(contentsOf: url) else { error = "Could not open \(url.lastPathComponent)"; return }
        overlay = DesignOverlay(image: image, fit: DesignOverlay.detectFit(image: image, snapshot: snapshot))
    }

    func nudgeOverlay(dx: Double, dy: Double) {
        overlay?.offset.width += dx
        overlay?.offset.height += dy
    }

    func accessibilityItem(for node: UINode?) -> AccessibilityItem? {
        guard let node else { return nil }
        return accessibilityItems.first { $0.node.id == node.id }
    }

    /// Text for the clipboard: size and position of the selected node in dp.
    func describeSelection() -> String? {
        guard let snapshot, let node = selected else { return nil }
        let r = node.bounds
        return "\(node.label): \(Int(snapshot.dp(r.width).rounded())) × \(Int(snapshot.dp(r.height).rounded())) dp at (\(Int(snapshot.dp(r.minX).rounded())), \(Int(snapshot.dp(r.minY).rounded()))) dp"
    }

    /// Rough font size for single-line text nodes: Android line height is about 1.25 × the sp size.
    func estimatedTextSize(_ node: UINode) -> Int? {
        guard let snapshot, !node.text.isEmpty || node.className.hasSuffix("TextView") else { return nil }
        let heightDp = snapshot.dp(node.bounds.height)
        guard heightDp > 8, heightDp < 64 else { return nil }
        return Int((heightDp / 1.25).rounded())
    }
}
