import Foundation
import Observation

/// Device facts for the header block. Loaded per selection and on the same stale-refresh path as features.
@MainActor
@Observable
final class DeviceInfoStore {
    private var info: DeviceInfo?
    var isExpanded: Bool = UserDefaults.standard.bool(forKey: DeviceInfoStore.expandedKey) {
        didSet { UserDefaults.standard.set(isExpanded, forKey: Self.expandedKey) }
    }

    private let reader: DeviceInfoReading
    private var loadedFor: String?
    private var loadedAt: Date = .distantPast
    private static let expandedKey = "panel.deviceInfoExpanded"
    private static let staleAfter: TimeInterval = 5

    /// Facts only for the device they were read from; never the last device's after it disconnects.
    func info(for device: Device?) -> DeviceInfo? {
        guard let device, device.serial == loadedFor else { return nil }
        return info
    }

    init(reader: DeviceInfoReading) {
        self.reader = reader
    }

    func load(_ context: DeviceContext) async {
        if loadedFor != context.device.serial { info = nil }
        let fresh = try? await reader.info(on: context.device, adb: context.adb)
        guard !Task.isCancelled else { return }  // device switched while reading
        if fresh != info { info = fresh }
        loadedFor = context.device.serial
        loadedAt = Date()
    }

    func loadIfStale(_ context: DeviceContext) async {
        guard loadedFor != context.device.serial || Date().timeIntervalSince(loadedAt) > Self.staleAfter else { return }
        await load(context)
    }
}
