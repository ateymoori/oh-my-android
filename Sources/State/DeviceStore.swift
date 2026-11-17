import Foundation
import Observation

/// Connected devices and the current selection. Updates arrive from adb's own device tracker; while no
/// device is ready (adb server restarting, emulator offline, phone unauthorized) a short recovery loop
/// re-checks every few seconds until one is, then stops.
@MainActor
@Observable
final class DeviceStore {
    private(set) var devices: [Device] = []
    /// Last adb failure, shown when the list is empty.
    private(set) var lastError: String?
    /// Set by `select` (the user) or by `refresh` (automatic). Only the user's choice is remembered.
    private(set) var selected: Device?
    private static let lastSerialKey = AgentSettings.panelDeviceKey
    private static let recoveryInterval: Duration = .seconds(4)

    private let adb: ADBClient
    private let tracker: DeviceTracking
    private var trackingTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    /// Refreshes can overlap (tracker, recovery loop, restart); only the newest one's list is applied.
    private var generation = 0

    init(adb: ADBClient, tracker: DeviceTracking) {
        self.adb = adb
        self.tracker = tracker
    }

    /// Starts the adb server first: a server spawned implicitly by the tracker would inherit its pipe.
    func start(startServer: @escaping @Sendable () async -> Void) {
        trackingTask?.cancel()
        trackingTask = Task { [weak self, tracker] in
            await startServer()
            await self?.refresh()  // also when the tracker cannot connect: shows the adb error
            for await _ in tracker.events() {
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// Called on quit: closes the connection to the adb server.
    func stop() {
        trackingTask?.cancel()
        recoveryTask?.cancel()
        tracker.stop()
    }

    /// The user's choice: it becomes the device the panel returns to and the MCP server's default.
    func select(_ device: Device) {
        selected = device
        UserDefaults.standard.set(device.serial, forKey: Self.lastSerialKey)
    }

    func refresh() async {
        generation += 1
        let current = generation
        let result: Result<[Device], any Error>
        do { result = .success(try await adb.devices()) } catch { result = .failure(error) }
        guard current == generation else { return }  // a newer refresh started meanwhile; its list wins
        switch result {
        case .success(let list):
            lastError = nil
            if list != devices { devices = list }
        case .failure(let error):
            lastError = error.localizedDescription
            devices = []
        }
        if let selected, let updated = devices.first(where: { $0.id == selected.id }), updated.isReady {
            if updated != selected { self.selected = updated }
        } else {
            // Come back to the device used last time; otherwise the first one that is ready.
            let last = UserDefaults.standard.string(forKey: Self.lastSerialKey)
            selected = devices.first { $0.isReady && $0.serial == last } ?? devices.first { $0.isReady }
            // First run: remember the automatic choice, so the MCP server has a default too.
            if last == nil, let serial = selected?.serial { UserDefaults.standard.set(serial, forKey: Self.lastSerialKey) }
        }
        updateRecovery()
    }

    /// Manual fix for a stuck adb: restart the server, then re-read.
    func restartServer() async {
        lastError = nil
        try? await adb.restartServer()
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    private func updateRecovery() {
        // Also while a device boots: adb reports no event when boot completes.
        let needsRecovery = selected == nil || devices.contains { $0.isOnline && !$0.isBooted }
        if needsRecovery, recoveryTask == nil {
            recoveryTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.recoveryInterval)
                    guard let self, !Task.isCancelled else { return }
                    await self.refresh()
                }
            }
        } else if !needsRecovery {
            recoveryTask?.cancel()
            recoveryTask = nil
        }
    }
}
