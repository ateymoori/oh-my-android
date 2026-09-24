import Foundation

/// Services shared by all tools for the life of the server process.
final class ToolEnvironment: Sendable {
    let sdk: AndroidSDK?
    let layout: LayoutSnapshotReading = UIAutomatorSnapshotReader()
    let appData: AppDataReading = RunAsAppDataReader()
    /// Last UI tree per device, so `tap` and `swipe` can target a ref from `get_ui`.
    let hierarchies = HierarchyCache()
    private let bridge: AndroidDebugBridge?
    private let foreground: ForegroundAppReading = ForegroundAppReader()
    private let server = ADBServerStarter()

    init(sdk: AndroidSDK?) {
        self.sdk = sdk
        bridge = sdk.map { AndroidDebugBridge(sdk: $0, runner: ProcessShellRunner()) }
    }

    /// adb, with its server running. Started without pipes once, before any piped command can spawn it.
    func adb() async throws -> AndroidDebugBridge {
        guard let bridge else {
            throw AppError("Android SDK not found. Set ANDROID_HOME in this MCP server's env, or choose the SDK in Oh My Android → Settings.")
        }
        await server.start(bridge)
        return bridge
    }

    func context(serial: String?) async throws -> DeviceContext {
        let adb = try await adb()
        let devices = try await adb.devices()
        let device: Device
        if let serial {
            guard let match = devices.first(where: { $0.serial == serial }) else {
                throw AppError("No device \(serial). Connected: \(Self.describe(devices)).")
            }
            device = match
        } else {
            let ready = devices.filter(\.isReady)
            switch ready.count {
            case 0:
                throw AppError(devices.isEmpty
                    ? "No device connected. Start an emulator (list_devices shows the AVDs) or connect a phone with USB debugging on."
                    : "No device ready: \(Self.describe(devices)).")
            case 1:
                device = ready[0]
            default:
                // Several: the one selected in the Oh My Android panel, else ask.
                guard let panel = AgentSettings.panelDevice, let selected = ready.first(where: { $0.serial == panel }) else {
                    throw AppError("Several devices are ready; pass device: \(ready.map(\.serial).joined(separator: ", ")).")
                }
                device = selected
            }
        }
        if let problem = device.problem { throw AppError("\(device.serial) is \(problem).") }
        return DeviceContext(device: device, adb: adb, foreground: foreground, host: HostActions())
    }

    private static func describe(_ devices: [Device]) -> String {
        devices.isEmpty ? "none" : devices.map { "\($0.serial) (\($0.problem ?? "ready"))" }.joined(separator: ", ")
    }
}

/// Starts the adb server at most once per process.
private actor ADBServerStarter {
    private var started = false

    func start(_ adb: AndroidDebugBridge) async {
        guard !started else { return }
        started = true
        await adb.startServer()
    }
}

actor HierarchyCache {
    private var latest: [String: UIHierarchy] = [:]

    func store(_ hierarchy: UIHierarchy, for serial: String) { latest[serial] = hierarchy }
    func hierarchy(for serial: String) -> UIHierarchy? { latest[serial] }
}

extension ToolCall {
    /// Reads the UI tree and remembers it, so its refs work in `tap` and `swipe`.
    func freshHierarchy(_ context: DeviceContext) async throws -> UIHierarchy {
        let hierarchy = try await environment.layout.hierarchy(on: context.device, adb: context.adb)
        await environment.hierarchies.store(hierarchy, for: context.device.serial)
        return hierarchy
    }

    /// Node for a ref from the latest `get_ui` or `accessibility_audit` of this device.
    func node(ref: Int, _ context: DeviceContext) async throws -> (UINode, UIHierarchy) {
        guard let hierarchy = await environment.hierarchies.hierarchy(for: context.device.serial) else {
            throw ToolInputError("No UI tree yet. Call get_ui first, then use its [ref] numbers.")
        }
        guard let node = hierarchy.root.first(where: { $0.id == ref }) else {
            throw ToolInputError("Ref \(ref) is not in the latest UI tree. Call get_ui again.")
        }
        return (node, hierarchy)
    }

    /// `package` argument, or the app on screen. Validated: it goes into device shell commands.
    func package(_ context: DeviceContext) async throws -> String {
        if let package = try arguments.string("package") {
            guard package.wholeMatch(of: /[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+/) != nil else {
                throw ToolInputError("package must be an Android package name such as com.example.app.")
            }
            return package
        }
        return try await context.foregroundPackage()
    }
}

extension UINode {
    /// Depth-first search, root included.
    func first(where predicate: (UINode) -> Bool) -> UINode? {
        if predicate(self) { return self }
        for child in children { if let match = child.first(where: predicate) { return match } }
        return nil
    }

    /// Depth-first list of every node, root included.
    var flattened: [UINode] { [self] + children.flatMap(\.flattened) }
}
