import Foundation
import Observation

/// Emulators that can be started from the panel, and the one starting now.
@MainActor
@Observable
final class EmulatorStore {
    private(set) var avds: [String] = []
    /// AVD started from the panel that has not shown up as a device yet.
    private(set) var starting: String?
    private let sdk: AndroidSDK
    private var startTimeout: Task<Void, Never>?
    /// A cold boot can take a minute or two; after that the panel stops saying "Starting".
    private static let startLimit: Duration = .seconds(180)

    init(sdk: AndroidSDK) {
        self.sdk = sdk
    }

    /// Read on demand (when the panel has no device), not at launch: listing spawns a process.
    func reload() async {
        let found = await EmulatorLauncher.avds(sdk)
        if found != avds { avds = found }
    }

    func start(_ avd: String, onFailure: @escaping @MainActor (String) -> Void) {
        guard starting == nil else { return }
        do {
            try EmulatorLauncher.launch(avd, sdk: sdk) { [weak self] status in
                Task { @MainActor in
                    guard let self, self.starting == avd else { return }
                    self.finishStarting()
                    // Exit 0 is a normal close by the user; anything else before boot is a failed start.
                    if status != 0 { onFailure("\(EmulatorLauncher.displayName(avd)) did not start (exit \(status)). Is it open in Android Studio?") }
                }
            }
        } catch {
            return onFailure("Could not start \(EmulatorLauncher.displayName(avd)): \(error.localizedDescription)")
        }
        starting = avd
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.startLimit)
            guard !Task.isCancelled else { return }
            self?.finishStarting()
        }
    }

    /// Called when devices change: the emulator is up once any emulator is ready.
    func devicesChanged(_ devices: [Device]) {
        guard let starting else { return }
        if devices.contains(where: { $0.isEmulator && $0.isReady && ($0.avdName == nil || $0.avdName == starting) }) {
            finishStarting()
        }
    }

    private func finishStarting() {
        starting = nil
        startTimeout?.cancel()
        startTimeout = nil
    }
}
