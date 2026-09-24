import Foundation
import Observation

/// Composition root shared with the UI through the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let sdk: AndroidSDK?
    let adb: ADBClient?
    let devices: DeviceStore?
    let features = FeatureStore()
    let deviceInfo = DeviceInfoStore(reader: DeviceInfoReader())
    let emulators: EmulatorStore?

    private let foregroundReader: ForegroundAppReading = ForegroundAppReader()
    /// Filled by the app delegate once windows exist.
    var host = HostActions()
    private static let dockKey = "panel.dockToEmulator"
    private static let pinKey = "panel.pinned"

    /// Pinned: floats above all windows on every Space and docks to the emulator.
    /// Unpinned: a normal window that stays on the Space where it was left.
    var isPinned: Bool = UserDefaults.standard.object(forKey: AppModel.pinKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isPinned, forKey: Self.pinKey) }
    }

    var dockToEmulator: Bool = UserDefaults.standard.object(forKey: AppModel.dockKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(dockToEmulator, forKey: Self.dockKey) }
    }

    init(sdk: AndroidSDK? = AndroidSDK.locate()) {
        self.sdk = sdk
        let bridge = sdk.map { AndroidDebugBridge(sdk: $0, runner: ProcessShellRunner()) }
        adb = bridge
        devices = bridge.map { DeviceStore(adb: $0, tracker: ADBDeviceTracker(adb: $0.sdk.adb)) }
        emulators = sdk.map(EmulatorStore.init)
        if let bridge { devices?.start { await bridge.startServer() } }
    }

    var context: DeviceContext? {
        guard let adb, let device = devices?.selected else { return nil }
        return DeviceContext(device: device, adb: adb, foreground: foregroundReader, host: host)
    }

    /// What the panel shows. Every situation without a usable device has one case, so the UI covers
    /// them all and none can show stale device data.
    enum PanelState {
        case sdkMissing
        case adbFailed(String)
        case starting(avd: String)
        case booting(Device)
        case unauthorized(Device)
        case offline(Device)
        case noDevice
        case ready(DeviceContext)
    }

    var panelState: PanelState {
        guard let devices else { return .sdkMissing }
        if let context { return .ready(context) }
        if let avd = emulators?.starting { return .starting(avd: avd) }
        if let error = devices.lastError { return .adbFailed(error) }
        if let device = devices.devices.first(where: { $0.state == .unauthorized }) { return .unauthorized(device) }
        if let device = devices.devices.first(where: { !$0.isReady }) {
            // Starting: an emulator is offline until adbd runs; any device is online before boot completes.
            return device.isOnline || device.isEmulator ? .booting(device) : .offline(device)
        }
        return .noDevice
    }

    /// Full read of the selected device: feature values and device facts.
    func reload() async {
        guard let context else { return }
        async let info: () = deviceInfo.load(context)
        async let values: () = features.refreshAll(context)
        _ = await (info, values)
    }

    /// Re-read only when the last read is old. Called when the user's attention returns to the panel.
    func reloadIfStale() async {
        guard let context else { return }
        async let info: () = deviceInfo.loadIfStale(context)
        async let values: () = features.refreshIfStale(context)
        _ = await (info, values)
    }
}
