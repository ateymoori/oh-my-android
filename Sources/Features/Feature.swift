import Foundation

/// Declaration order is display order: most-used blocks first, emulator-only simulation last.
enum FeatureCategory: String, CaseIterable, Identifiable, Sendable {
    case appearance, app, capture, network, layout, accessibility, navigation, simulate, snapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .app: "App"
        case .capture: "Capture"
        case .network: "Network"
        case .layout: "Layout & performance"
        case .accessibility: "Accessibility"
        case .navigation: "Navigation & input"
        case .simulate: "Simulate"
        case .snapshots: "Snapshots"
        }
    }
}

/// UI the app shell offers to features (windows, pickers, clipboard, Finder). Keeps features free of AppKit.
struct HostActions: Sendable {
    var openDataInspector: @MainActor @Sendable (DeviceContext) -> Void = { _ in }
    /// Optional URL: a design image to lay over the screenshot.
    var openLayoutInspector: @MainActor @Sendable (DeviceContext, URL?) -> Void = { _, _ in }
    /// Open panel for one file with the given extension; nil when cancelled.
    var chooseFile: @MainActor @Sendable (_ fileExtension: String, _ message: String) async -> URL? = { _, _ in nil }
    var copyImage: @MainActor @Sendable (Data) -> Void = { _ in }
    var reveal: @MainActor @Sendable (URL) -> Void = { _ in }
}

/// Everything a feature needs to act on one device.
struct DeviceContext: Sendable {
    let device: Device
    let adb: ADBClient
    let foreground: ForegroundAppReading
    let host: HostActions

    @discardableResult func shell(_ command: String) async throws -> String { try await adb.shell(device, command) }
    @discardableResult func console(_ arguments: String...) async throws -> String { try await adb.console(device, arguments) }

    func putSetting(_ namespace: String, _ key: String, _ value: String) async throws {
        try await shell("settings put \(namespace) \(key) \(value)")
    }

    /// Sets a `debug.*` property and asks the system server to re-read it, so overlays apply live.
    func setDebugProperty(_ name: String, _ value: String) async throws {
        try await shell("setprop \(name) \(value) && service call activity 1599295570 >/dev/null")
    }

    /// Package of the app on screen, read at the moment of the action.
    func foregroundPackage() async throws -> String {
        guard let package = try await foreground.package(on: device, adb: adb) else {
            throw AppError("No app in the foreground.")
        }
        return package
    }
}

/// Last known state of a feature on the device.
enum FeatureValue: Equatable, Sendable {
    case toggle(Bool)
    case number(Double)
    case choice(String?)
}

/// Base contract. Every capability of the app is one small type conforming to a refinement below.
protocol Feature: Sendable {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    var category: FeatureCategory { get }
    /// Console-backed features only work on emulators.
    var requiresEmulator: Bool { get }
    var help: String { get }
}

extension Feature {
    var requiresEmulator: Bool { false }
    var help: String { title }
    func supports(_ device: Device) -> Bool { !requiresEmulator || device.isEmulator }
}

/// One shell command plus a parser. Features that expose this are read together in a single adb
/// round-trip, so refreshing the whole panel costs one process instead of one per feature.
struct DeviceRead: Sendable {
    let command: String
    let parse: @Sendable (String) -> FeatureValue?
}

protocol BatchReadable: Feature {
    var read: DeviceRead { get }
}

extension BatchReadable {
    /// Individual read for callers outside the batch (after an action, for example).
    func readValue(_ context: DeviceContext) async throws -> FeatureValue? {
        read.parse(try await context.shell(read.command))
    }
}

/// On/off state that can be read back from the device.
protocol ToggleFeature: Feature {
    func isOn(_ context: DeviceContext) async throws -> Bool
    func setOn(_ on: Bool, _ context: DeviceContext) async throws
}

/// Discrete numeric value stepped up or down.
protocol StepperFeature: Feature {
    var steps: [Double] { get }
    func value(_ context: DeviceContext) async throws -> Double
    func setValue(_ value: Double, _ context: DeviceContext) async throws
    func label(for value: Double) -> String
}

struct FeatureOption: Identifiable, Hashable, Sendable {
    let id: String
    /// Short name, used as the icon caption when selected.
    let title: String
    /// Optional explanation shown in the menu only.
    var detail: String? = nil

    var menuTitle: String { detail.map { "\(title) — \($0)" } ?? title }
}

/// One of several named options. `selection` may return nil when the device offers no read-back.
protocol ChoiceFeature: Feature {
    var options: [FeatureOption] { get }
    func selection(_ context: DeviceContext) async throws -> String?
    func select(_ optionID: String, _ context: DeviceContext) async throws
}

extension ToggleFeature where Self: BatchReadable {
    func isOn(_ context: DeviceContext) async throws -> Bool {
        if case .toggle(let on)? = try await readValue(context) { return on }
        return false
    }
}

extension StepperFeature where Self: BatchReadable {
    func value(_ context: DeviceContext) async throws -> Double {
        if case .number(let value)? = try await readValue(context) { return value }
        return 1.0
    }
}

extension ChoiceFeature where Self: BatchReadable {
    func selection(_ context: DeviceContext) async throws -> String? {
        if case .choice(let id)? = try await readValue(context) { return id }
        return nil
    }
}

/// Fire-and-forget command. May return a short confirmation message.
protocol ActionFeature: Feature {
    var isDestructive: Bool { get }
    func perform(_ context: DeviceContext) async throws -> String?
}

extension ActionFeature { var isDestructive: Bool { false } }

/// Command that needs one line of user text.
protocol TextActionFeature: Feature {
    var placeholder: String { get }
    var submitTitle: String { get }
    func perform(_ text: String, _ context: DeviceContext) async throws -> String?
}

extension TextActionFeature { var submitTitle: String { "Send" } }
