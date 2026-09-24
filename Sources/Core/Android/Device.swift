import Foundation

/// One connected Android target: emulator, USB, or Wi‑Fi device.
struct Device: Identifiable, Hashable, Sendable {
    /// adb connection state. Only `device` accepts commands.
    enum State: String, Sendable {
        case device, unauthorized, offline, other

        var problem: String? {
            switch self {
            case .device: nil
            case .unauthorized: "accept USB debugging on the phone"
            case .offline: "offline"
            case .other: "not ready"
            }
        }
    }

    let serial: String
    let model: String
    var state: State = .device
    var avdName: String?

    var id: String { serial }
    var isEmulator: Bool { serial.hasPrefix("emulator-") }
    var isReady: Bool { state == .device }
    var displayName: String { avdName?.replacingOccurrences(of: "_", with: " ") ?? model }
    var symbol: String { isEmulator ? "macbook.and.iphone" : "iphone" }
    /// Console port of an emulator serial such as "emulator-5554".
    var consolePort: Int? { isEmulator ? Int(serial.dropFirst("emulator-".count)) : nil }
}
