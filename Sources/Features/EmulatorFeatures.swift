import Foundation

enum EmulatorFeatures {
    static let rotate = ConsoleActionFeature(
        id: "emulator.rotate", title: "Rotate", symbol: "rotate.right.fill", category: .appearance, arguments: ["rotate"]
    )
    static let fingerprint = ConsoleActionFeature(
        id: "emulator.fingerprint", title: "Fingerprint", symbol: "touchid", category: .simulate, arguments: ["finger", "touch", "1"]
    )
    static let incomingCall = ConsoleActionFeature(
        id: "emulator.call", title: "Call", symbol: "phone.arrow.down.left.fill", category: .simulate,
        arguments: ["gsm", "call", "5551234567"]
    )
    static let snapshotSave = ConsoleActionFeature(
        id: "emulator.snapshotSave", title: "Save state", symbol: "square.and.arrow.down.fill", category: .snapshots,
        arguments: ["avd", "snapshot", "save", "ohmyandroid_clean"], message: "Snapshot saved"
    )
    static let snapshotLoad = ConsoleActionFeature(
        id: "emulator.snapshotLoad", title: "Restore", symbol: "clock.arrow.circlepath", category: .snapshots,
        arguments: ["avd", "snapshot", "load", "ohmyandroid_clean"], message: "Snapshot restored"
    )
}
