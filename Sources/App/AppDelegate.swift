import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updates = UpdateController()
    private(set) var panel: PanelController?
    private var inspector: InspectorWindowController?
    private var layoutInspector: LayoutInspectorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let inspector = InspectorWindowController(store: InspectorStore(reader: RunAsAppDataReader()))
        let layoutInspector = LayoutInspectorWindowController(store: LayoutInspectorStore(reader: UIAutomatorSnapshotReader()))
        self.inspector = inspector
        self.layoutInspector = layoutInspector
        model.host = HostActions(
            openDataInspector: { context in inspector.show(context: context) },
            openLayoutInspector: { context, overlay in layoutInspector.show(context: context, overlay: overlay) },
            chooseFile: { fileExtension, message in
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
                panel.allowsMultipleSelection = false
                panel.message = message
                NSApp.activate()  // the floating panel never activates the app; the dialog would open behind
                return await panel.begin() == .OK ? panel.url : nil
            },
            copyImage: { data in
                guard let image = NSImage(data: data) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            },
            reveal: { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
        )
        panel = PanelController(model: model)
        panel?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.devices?.stop()
        inspector?.close()
    }

    /// Menu-bar entry points; the panel icons call the same host actions.
    func openLayoutInspector() { if let context = model.context { model.host.openLayoutInspector(context, nil) } }
    func openDataInspector() { if let context = model.context { model.host.openDataInspector(context) } }

    /// PNG/JPEG opened with the app (Dock drop, "Open with", `open -a`) becomes a design overlay.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { FileDrop.imageExtensions.contains($0.pathExtension.lowercased()) }) else { return }
        guard let context = model.context else {
            model.features.show(Toast(kind: .error, message: "Connect a device to compare \(url.lastPathComponent)."))
            panel?.show()
            return
        }
        layoutInspector?.show(context: context, overlay: url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
