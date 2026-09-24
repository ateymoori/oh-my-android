import Foundation

/// Devices, their state, and the test settings the panel offers.
enum DeviceTools {
    static let all = [listDevices, getDeviceState, setDeviceSettings]

    static let listDevices = Tool(
        name: "list_devices",
        title: "List devices",
        description: "Connected emulators and phones with their state, and the emulators (AVDs) that can be started.",
        effect: .read,
        targetsDevice: false
    ) { call in
        let adb = try await call.environment.adb()
        let devices = try await adb.devices()
        let panel = AgentSettings.panelDevice
        var lines = devices.map { device in
            let kind = device.isEmulator ? "emulator" : "phone"
            let state = device.state.problem ?? "ready"
            return "\(device.serial)  \(device.displayName)  \(kind)  \(state)\(device.serial == panel ? "  (selected in panel)" : "")"
        }
        if lines.isEmpty { lines.append("No device connected.") }
        if let avds = try? await call.environment.availableAVDs(), !avds.isEmpty {
            lines.append("AVDs: " + avds.joined(separator: ", ") + " (start with: emulator -avd <name>)")
        }
        return .text(lines.joined(separator: "\n"))
    }

    static let getDeviceState = Tool(
        name: "get_device_state",
        title: "Get device state",
        description: "Device facts, app on screen, and current test settings, with the same names set_device_settings takes.",
        effect: .read
    ) { call in
        let context = try await call.device()
        async let info = DeviceInfoReader().info(on: context.device, adb: context.adb)
        async let foreground = try? context.foregroundPackage()
        async let settings = DeviceSettings.state(context)
        let facts = try await info
        let device = context.device
        return .text([
            "\(device.displayName) (\(device.serial), \(device.isEmulator ? "emulator" : "phone")): Android \(facts.androidVersion), API \(facts.apiLevel), \(facts.hasPlayServices ? "Google Play" : "no Google Play"), \(facts.abi)",
            "Screen: \(facts.display)\(dpSize(facts.display))",
            "App on screen: \(await foreground ?? "none")",
            "Settings: " + (await settings),
        ].joined(separator: "\n"))
    }

    /// " = 411x914 dp" from "1080×2400 · 420 dpi".
    private static func dpSize(_ display: String) -> String {
        guard let match = display.firstMatch(of: /(\d+)×(\d+) · (\d+) dpi/),
              let width = Double(match.1), let height = Double(match.2), let dpi = Double(match.3), dpi > 0 else { return "" }
        return " = \(Int((width * 160 / dpi).rounded()))x\(Int((height * 160 / dpi).rounded())) dp"
    }

    static let setDeviceSettings = Tool(
        name: "set_device_settings",
        title: "Set device settings",
        description: "Change test settings; pass only the ones to change. Applies live, no restart. Returns the new settings.",
        effect: .control,
        idempotent: true,
        parameters: DeviceSettings.all.map(\.parameter)
    ) { call in
        let context = try await call.device()
        let requested = DeviceSettings.all.filter { call.arguments.has($0.key) }
        guard !requested.isEmpty else { throw ToolInputError("Pass at least one setting.") }
        var failures: [String] = []
        for setting in requested {
            if setting.emulatorOnly, !context.device.isEmulator {
                failures.append("\(setting.key): emulator only")
                continue
            }
            do { try await setting.apply(call.arguments, context) } catch let error as ToolInputError { throw error } catch {
                failures.append("\(setting.key): \(error.localizedDescription)")
            }
        }
        let state = await DeviceSettings.state(context)
        guard failures.isEmpty else { return .error("Failed: \(failures.joined(separator: "; ")).\nSettings: \(state)") }
        return .text("Settings: \(state)")
    }
}

/// One test setting: its parameter, how to read it, how to change it. Reuses the panel's features.
struct DeviceSetting: Sendable {
    let key: String
    let parameter: ToolParameter
    /// Read in the shared batch; nil for emulator console settings.
    var read: DeviceRead?
    var emulatorOnly = false
    let apply: @Sendable (Arguments, DeviceContext) async throws -> Void
}

enum DeviceSettings {
    static let all: [DeviceSetting] = [
        toggle("dark_mode", "Dark theme.", DarkModeFeature()),
        DeviceSetting(
            key: "font_scale", parameter: .number("font_scale", "Font size multiplier. 1 is default; 1.3 and 2 test large text.", range: 0.5...3),
            read: FontScaleFeature().read
        ) { arguments, context in
            try await FontScaleFeature().setValue(try arguments.double("font_scale", in: 0.5...3)!, context)
        },
        DeviceSetting(
            key: "display_scale", parameter: .number("display_scale", "Display size (dp scale). 1 is default; 1.35 makes everything larger.", range: 0.5...2),
            read: DeviceRead(command: "wm density") { output in
                let density = WindowManagerOutput.density(output)
                guard let physical = density.physical else { return nil }
                return .number(Double(density.override ?? physical) / Double(physical))
            }
        ) { arguments, context in
            try await DisplayScaleFeature().setValue(try arguments.double("display_scale", in: 0.5...2)!, context)
        },
        DeviceSetting(
            key: "locale", parameter: .string("locale", "BCP 47 locale, e.g. en-US, sv-SE; ar-EG for RTL; en-XA (long text) and ar-XB (RTL) pseudo-locales."),
            read: DeviceLanguageFeature().read
        ) { arguments, context in
            let locale = try arguments.requiredString("locale")
            guard locale.wholeMatch(of: /[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*/) != nil else { throw ToolInputError("locale must look like en-US.") }
            try await DeviceLanguageFeature().select(locale, context)
        },
        DeviceSetting(
            key: "orientation", parameter: .string("orientation", "Screen rotation lock, or auto.", oneOf: ["portrait", "landscape", "auto"]),
            read: DeviceRead(command: "settings get system accelerometer_rotation; settings get system user_rotation") { output in
                let values = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                guard values.count == 2 else { return nil }
                return .choice(values[0] == "1" ? "auto" : (Int(values[1]) ?? 0) % 2 == 0 ? "portrait" : "landscape")
            }
        ) { arguments, context in
            switch try arguments.choice("orientation", ["portrait", "landscape", "auto"]) {
            case "auto": try await context.putSetting("system", "accelerometer_rotation", "1")
            case let value?:
                try await context.putSetting("system", "accelerometer_rotation", "0")
                try await context.putSetting("system", "user_rotation", value == "portrait" ? "0" : "1")
            case nil: break
            }
        },
        toggle("talkback", "TalkBack screen reader.", TalkBackFeature()),
        toggle("bold_text", "Bold text (Android 12+).", BoldTextFeature()),
        DeviceSetting(
            key: "animations", parameter: .boolean("animations", "System animations. false makes UI tests stable."),
            read: DeviceRead(command: AnimationsOffFeature().read.command) { output in
                guard case .toggle(let off)? = AnimationsOffFeature().read.parse(output) else { return nil }
                return .toggle(!off)
            }
        ) { arguments, context in
            try await AnimationsOffFeature().setOn(!(try arguments.bool("animations")!), context)
        },
        toggle("layout_bounds", "Show layout bounds overlay.", catalog("debug.layoutBounds")),
        toggle("show_taps", "Show touches on screen.", catalog("debug.showTaps")),
        toggle("airplane_mode", "Airplane mode: no network.", AirplaneModeFeature()),
        toggle("wifi", "Wi-Fi.", WifiFeature()),
        toggle("mobile_data", "Mobile data.", MobileDataFeature()),
        DeviceSetting(
            key: "network_speed", parameter: .string("network_speed", "Emulator only. Bandwidth and latency profile.", oneOf: NetworkProfileFeature().options.map(\.id)),
            emulatorOnly: true
        ) { arguments, context in
            let feature = NetworkProfileFeature()
            try await feature.select(try arguments.choice("network_speed", feature.options.map(\.id))!, context)
        },
        DeviceSetting(key: "location", parameter: .string("location", "Emulator only. GPS fix as \"lat,lon\", e.g. \"59.3293,18.0686\"."), emulatorOnly: true) { arguments, context in
            _ = try await CustomLocationFeature().perform(try arguments.requiredString("location"), context)
        },
        DeviceSetting(key: "battery_level", parameter: .integer("battery_level", "Emulator only. Battery percent.", range: 0...100), emulatorOnly: true) { arguments, context in
            try await BatteryLevelFeature().select(String(try arguments.int("battery_level", in: 0...100)!), context)
        },
        DeviceSetting(key: "charging", parameter: .boolean("charging", "Emulator only. Charger connected."), emulatorOnly: true) { arguments, context in
            try await ChargingFeature().setOn(try arguments.bool("charging")!, context)
        },
    ]

    /// Current values as `key=value`, in parameter order. Device settings come from one adb call.
    static func state(_ context: DeviceContext) async -> String {
        let readable = all.compactMap { setting in setting.read.map { (id: setting.key, read: $0) } }
        var values = await BatchReader().read(readable, context).mapValues(text)
        if context.device.isEmulator {
            async let speed = try? NetworkProfileFeature().selection(context)
            async let battery = try? BatteryLevelFeature().selection(context)
            async let charging = try? ChargingFeature().isOn(context)
            values["network_speed"] = await speed ?? "custom"
            values["battery_level"] = await battery ?? nil
            values["charging"] = await charging.map { $0 ? "on" : "off" }
        }
        return all.compactMap { setting in values[setting.key].map { "\(setting.key)=\($0)" } }.joined(separator: " ")
    }

    private static func text(_ value: FeatureValue) -> String {
        switch value {
        case .toggle(let on): on ? "on" : "off"
        case .number(let number): String(format: "%.2f", number).replacing(/\.?0+$/, with: "")
        case .choice(let id): id ?? "unknown"
        }
    }

    private static func toggle(_ key: String, _ description: String, _ feature: some ToggleFeature & BatchReadable) -> DeviceSetting {
        DeviceSetting(key: key, parameter: .boolean(key, description), read: feature.read) { arguments, context in
            try await feature.setOn(try arguments.bool(key)!, context)
        }
    }

    /// A panel feature by id. The ids are fixed in FeatureCatalog; a rename fails at launch, not silently.
    private static func catalog(_ id: String) -> any ToggleFeature & BatchReadable {
        guard let feature = FeatureCatalog.all.first(where: { $0.id == id }) as? any ToggleFeature & BatchReadable else {
            fatalError("FeatureCatalog has no toggle \(id)")
        }
        return feature
    }
}

extension ToolEnvironment {
    /// Emulator images installed in the SDK.
    func availableAVDs() async throws -> [String] {
        guard let sdk else { return [] }
        let emulator = sdk.root.appending(path: "emulator/emulator")
        guard FileManager.default.isExecutableFile(atPath: emulator.path) else { return [] }
        let output = try await ProcessShellRunner(timeout: .seconds(10)).run(emulator, arguments: ["-list-avds"]).stdout
        return output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("INFO") }
    }
}
