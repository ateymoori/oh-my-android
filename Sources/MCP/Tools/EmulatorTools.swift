import Foundation

/// Emulator-only events and state snapshots, through the emulator console.
enum EmulatorTools {
    static let all = [emulatorAction]
    private static let actions = ["fingerprint", "incoming_call", "sms", "save_snapshot", "load_snapshot"]

    static let emulatorAction = Tool(
        name: "emulator_action",
        title: "Emulator action",
        description: """
        Emulator only. fingerprint: touch the sensor (enrolled finger 1). incoming_call and sms: from 5551234567. \
        save_snapshot / load_snapshot: save or restore the whole device state by name.
        """,
        effect: .destructive,
        parameters: [
            .string("action", "What to do.", required: true, oneOf: actions),
            .string("text", "sms: message text."),
            .string("name", "Snapshot name. Default ohmyandroid_clean (the panel's Save state)."),
        ]
    ) { call in
        let context = try await call.device()
        guard context.device.isEmulator else { throw AppError("\(context.device.serial) is a phone; emulator_action needs an emulator.") }
        let action = try call.arguments.choice("action", actions) ?? { throw ToolInputError("action is required.") }()
        let name = try call.arguments.string("name") ?? "ohmyandroid_clean"
        guard name.wholeMatch(of: /[A-Za-z0-9_.-]+/) != nil else { throw ToolInputError("name may use letters, digits, _ . - only.") }
        switch action {
        case "fingerprint": _ = try await EmulatorFeatures.fingerprint.perform(context)
        case "incoming_call": _ = try await EmulatorFeatures.incomingCall.perform(context)
        case "sms": _ = try await IncomingSMSFeature().perform(try call.arguments.requiredString("text"), context)
        case "save_snapshot": try await context.console("avd", "snapshot", "save", name)
        default: try await context.console("avd", "snapshot", "load", name)
        }
        return .text("Done: \(action)\(action.hasSuffix("snapshot") ? " \(name)" : "").")
    }
}
