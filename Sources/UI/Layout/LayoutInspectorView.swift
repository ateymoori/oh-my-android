import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Figma-style inspection of a frozen screen: hover shows an element and its size in dp, click selects,
/// hovering another element shows the distances between them, hovering a nested one shows paddings.
struct LayoutInspectorView: View {
    @Bindable var store: LayoutInspectorStore

    var body: some View {
        VStack(spacing: 0) {
            if store.overlay != nil { overlayBar; Divider() }
            HStack(spacing: 0) {
                content
                if store.showAccessibility { Divider(); AccessibilityListView(store: store) }
            }
            Divider()
            InfoBar(store: store)
        }
        .frame(minWidth: store.showAccessibility ? 800 : 460, idealWidth: store.showAccessibility ? 900 : 560, minHeight: 640, idealHeight: 980)
        .toolbar { toolbarItems }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .focusable()
        .onKeyPress(.leftArrow) { nudge(-1, 0) }
        .onKeyPress(.rightArrow) { nudge(1, 0) }
        .onKeyPress(.upArrow) { nudge(0, -1) }
        .onKeyPress(.downArrow) { nudge(0, 1) }
        .onKeyPress(.escape) { store.selected = nil; return .handled }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await store.capture() } } label: { Label("Capture", systemImage: "camera.viewfinder") }
                .keyboardShortcut("r", modifiers: .command)
                .help("Capture again: new screenshot and hierarchy (⌘R)")
            Toggle(isOn: $store.showGrid) { Label("8 dp grid", systemImage: "grid") }
                .keyboardShortcut("g", modifiers: .command)
                .help("8 dp baseline grid (⌘G)")
            Toggle(isOn: $store.showAccessibility) { Label("Accessibility", systemImage: "figure.stand") }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Accessibility mode: TalkBack order, roles, announcements, findings (⇧⌘A)")
            Button { pickOverlay() } label: { Label("Design overlay", systemImage: "rectangle.on.rectangle") }
                .keyboardShortcut("o", modifiers: .command)
                .help("Overlay a Figma export — or drop a PNG on this window (⌘O)")
            Button {
                if let text = store.describeSelection() { copy(text) }
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(store.selected == nil)
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy size and position of the selection (⌘C)")
        }
        ToolbarItem(placement: .status) {
            if store.isLoading { ProgressView().controlSize(.small) }
        }
    }

    private var overlayBar: some View {
        HStack(spacing: 10) {
            Picker("Scale", selection: Binding(get: { store.overlay?.fit ?? .fitWidth }, set: { store.overlay?.fit = $0 })) {
                ForEach(DesignOverlay.Fit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            .help("1×/2×/3× = Figma export scale (Figma px are dp). Fit width stretches to the screen.")
            Slider(value: Binding(get: { store.overlay?.opacity ?? 0.5 }, set: { store.overlay?.opacity = $0 }), in: 0...1)
                .frame(width: 120)
                .help("Opacity")
            Toggle(isOn: Binding(get: { store.overlay?.difference ?? false }, set: { store.overlay?.difference = $0 })) {
                Label("Difference", systemImage: "circle.lefthalf.striped.horizontal")
            }
            .toggleStyle(.button)
            .help("Difference blend: aligned pixels turn black, mismatches light up")
            if let offset = store.overlay?.offset {
                Text("offset \(Int(offset.width)), \(Int(offset.height)) dp").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                    .help("Arrow keys nudge 1 dp, ⇧ + arrows 10 dp")
            }
            Spacer()
            Button { store.overlay = nil } label: { Label("Remove overlay", systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.plain).help("Remove overlay")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot, let image = store.screenImage {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / snapshot.screen.width, geometry.size.height / snapshot.screen.height)
                let size = CGSize(width: snapshot.screen.width * scale, height: snapshot.screen.height * scale)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                    if let overlay = store.overlay {
                        let pixels = overlay.pixelSize(for: snapshot)
                        let dpToPx = snapshot.density / 160
                        Image(nsImage: overlay.image)
                            .resizable()
                            .frame(width: pixels.width * scale, height: pixels.height * scale)
                            .offset(x: overlay.offset.width * dpToPx * scale, y: overlay.offset.height * dpToPx * scale)
                            .opacity(overlay.difference ? 1 : overlay.opacity)
                            .blendMode(overlay.difference ? .difference : .normal)
                            .allowsHitTesting(false)
                    }
                    MeasurementCanvas(store: store, snapshot: snapshot, scale: scale)
                        .frame(width: size.width, height: size.height)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): store.hover(at: CGPoint(x: point.x / scale, y: point.y / scale))
                            case .ended: store.hover(at: nil)
                            }
                        }
                        .onTapGesture { point in store.click(at: CGPoint(x: point.x / scale, y: point.y / scale)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else if let error = store.error {
            ContentUnavailableView {
                Label("No snapshot", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await store.capture() } }
            }
        } else {
            ContentUnavailableView("Capturing…", systemImage: "viewfinder", description: Text("Screenshot and view hierarchy of the device."))
        }
    }

    private func nudge(_ dx: Double, _ dy: Double) -> KeyPress.Result {
        guard store.overlay != nil else { return .ignored }
        let step = NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0
        store.nudgeOverlay(dx: dx * step, dy: dy * step)
        return .handled
    }

    private func pickOverlay() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "Choose a Figma export (PNG at 1×, 2× or 3×)"
        if panel.runModal() == .OK, let url = panel.url { store.loadOverlay(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        FileDrop.load(providers, extensions: FileDrop.imageExtensions) { store.loadOverlay($0) }
    }
}

/// Selection, hover and color readout. Its own view: it changes on every pointer move, the rest of the window does not.
private struct InfoBar: View {
    let store: LayoutInspectorStore

    var body: some View {
        HStack(spacing: 16) {
            nodeSummary("Selected", store.selected, color: .red)
            nodeSummary("Hover", store.hovered, color: .blue)
            Spacer()
            if store.selected == nil, store.hovered == nil {
                Text("Click: select · Hover: measure").foregroundStyle(.tertiary).fixedSize()
            }
            if let pixel = store.hoveredColor {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(pixel.color).frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                    Text(pixel.hex)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Color under the cursor \(pixel.hex)")
                .help("Color under the cursor. ⇧⌘C copies it.")
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .background {
            Button("") { if let pixel = store.hoveredColor { copy(pixel.hex) } }
                .keyboardShortcut("c", modifiers: [.command, .shift]).hidden()
        }
    }

    @ViewBuilder
    private func nodeSummary(_ title: String, _ node: UINode?, color: Color) -> some View {
        if let node, let snapshot = store.snapshot {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(node.label).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
                Text("\(dp(node.bounds.width, snapshot)) × \(dp(node.bounds.height, snapshot)) dp").foregroundStyle(.secondary).fixedSize()
                Text("@ \(dp(node.bounds.minX, snapshot)), \(dp(node.bounds.minY, snapshot))").foregroundStyle(.tertiary).fixedSize()
                if let sp = store.estimatedTextSize(node) {
                    Text("≈ \(sp) sp").foregroundStyle(.secondary).help("Estimated from the text line height")
                }
                if store.showAccessibility, let item = store.accessibilityItem(for: node) {
                    Text("#\(item.order) \(item.role)").foregroundStyle(item.hasIssues ? .orange : .green).fixedSize()
                }
            }
        } else {
            Text("\(title): —").foregroundStyle(.tertiary)
        }
    }

    private func dp(_ pixels: Double, _ snapshot: LayoutSnapshot) -> Int { Int(snapshot.dp(pixels).rounded()) }
}

private extension PixelColor {
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Draws grid, outlines and measurement lines over the screenshot. All geometry in pixels × scale.
private struct MeasurementCanvas: View {
    let store: LayoutInspectorStore
    let snapshot: LayoutSnapshot
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            if store.showGrid { drawGrid(context, size) }
            if store.showAccessibility { drawAccessibility(context) }
            if let selected = store.selected { outline(context, selected.bounds, color: .red, width: 1.5) }
            if let hovered = store.hovered, hovered != store.selected {
                outline(context, hovered.bounds, color: .blue, width: 1)
                sizeLabel(context, hovered.bounds, color: .blue)
            }
            if let selected = store.selected {
                if let hovered = store.hovered, hovered != selected {
                    measure(context, from: selected.bounds, to: hovered.bounds)
                } else {
                    sizeLabel(context, selected.bounds, color: .red)
                }
            }
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
    }

    // MARK: - Drawing

    /// Numbered badge per screen-reader stop; orange when the audit found something.
    private func drawAccessibility(_ context: GraphicsContext) {
        for item in store.accessibilityItems {
            let r = scaled(item.node.bounds)
            let color: Color = item.hasIssues ? .orange : .green
            context.stroke(Path(r), with: .color(color.opacity(0.7)), lineWidth: 1)
            label(context, "\(item.order)", at: CGPoint(x: r.minX + 10, y: r.minY + 8), color: color)
        }
    }

    private func drawGrid(_ context: GraphicsContext, _ size: CGSize) {
        let step = store.gridStepDp * snapshot.density / 160 * scale
        guard step >= 3 else { return }
        var path = Path()
        for x in stride(from: 0, through: size.width, by: step) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
        for y in stride(from: 0, through: size.height, by: step) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
        context.stroke(path, with: .color(.cyan.opacity(0.25)), lineWidth: 0.5)
    }

    private func outline(_ context: GraphicsContext, _ rect: CGRect, color: Color, width: CGFloat) {
        context.stroke(Path(scaled(rect)), with: .color(color), lineWidth: width)
        context.fill(Path(scaled(rect)), with: .color(color.opacity(0.08)))
    }

    private func sizeLabel(_ context: GraphicsContext, _ rect: CGRect, color: Color) {
        let r = scaled(rect)
        label(context, "\(dp(rect.width)) × \(dp(rect.height))", at: CGPoint(x: r.midX, y: r.maxY + 10), color: color)
    }

    /// Figma rules: nested → paddings to each edge; separated → gap on each separated axis.
    private func measure(_ context: GraphicsContext, from a: CGRect, to b: CGRect) {
        let nested = a.contains(b) || b.contains(a)
        if nested {
            let outer = a.contains(b) ? a : b
            let inner = a.contains(b) ? b : a
            line(context, from: CGPoint(x: outer.minX, y: inner.midY), to: CGPoint(x: inner.minX, y: inner.midY), value: inner.minX - outer.minX)
            line(context, from: CGPoint(x: inner.maxX, y: inner.midY), to: CGPoint(x: outer.maxX, y: inner.midY), value: outer.maxX - inner.maxX)
            line(context, from: CGPoint(x: inner.midX, y: outer.minY), to: CGPoint(x: inner.midX, y: inner.minY), value: inner.minY - outer.minY)
            line(context, from: CGPoint(x: inner.midX, y: inner.maxY), to: CGPoint(x: inner.midX, y: outer.maxY), value: outer.maxY - inner.maxY)
            return
        }
        // Horizontal gap
        let y = overlapMid(a.minY...a.maxY, b.minY...b.maxY) ?? a.midY
        if b.minX >= a.maxX { line(context, from: CGPoint(x: a.maxX, y: y), to: CGPoint(x: b.minX, y: y), value: b.minX - a.maxX) }
        else if a.minX >= b.maxX { line(context, from: CGPoint(x: b.maxX, y: y), to: CGPoint(x: a.minX, y: y), value: a.minX - b.maxX) }
        // Vertical gap
        let x = overlapMid(a.minX...a.maxX, b.minX...b.maxX) ?? a.midX
        if b.minY >= a.maxY { line(context, from: CGPoint(x: x, y: a.maxY), to: CGPoint(x: x, y: b.minY), value: b.minY - a.maxY) }
        else if a.minY >= b.maxY { line(context, from: CGPoint(x: x, y: b.maxY), to: CGPoint(x: x, y: a.minY), value: a.minY - b.maxY) }
    }

    private func overlapMid(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat? {
        let low = max(a.lowerBound, b.lowerBound), high = min(a.upperBound, b.upperBound)
        return low < high ? (low + high) / 2 : nil
    }

    private func line(_ context: GraphicsContext, from: CGPoint, to: CGPoint, value: CGFloat) {
        guard value > 0.5 else { return }
        var path = Path()
        path.move(to: scaled(from)); path.addLine(to: scaled(to))
        context.stroke(path, with: .color(.red), lineWidth: 1)
        let mid = CGPoint(x: (scaled(from).x + scaled(to).x) / 2, y: (scaled(from).y + scaled(to).y) / 2)
        label(context, "\(dp(value))", at: mid, color: .red)
    }

    private func label(_ context: GraphicsContext, _ text: String, at point: CGPoint, color: Color) {
        let resolved = context.resolve(Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let rect = CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 2, width: size.width + 8, height: size.height + 4)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
        context.draw(resolved, at: point, anchor: .center)
    }

    private func dp(_ pixels: CGFloat) -> Int { Int(snapshot.dp(pixels).rounded()) }
    private func scaled(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale) }
    private func scaled(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scale, y: point.y * scale) }
}
