import Foundation

/// How much AI agents may do through the MCP server. Set in the app, checked by the server on every call.
enum AgentAccess: String, CaseIterable, Identifiable, Sendable, Comparable {
    case off
    /// Look only: screen, UI tree, audit, logs, app data. Nothing on the device changes.
    case readOnly = "read"
    /// Also tap, type, change settings and manage apps.
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .readOnly: "Read only"
        case .full: "Full control"
        }
    }

    var detail: String {
        switch self {
        case .off: "Agents can connect, but every tool call is refused."
        case .readOnly: "Agents can see the screen, UI tree, logs and app data. Nothing on the device changes."
        case .full: "Agents can also tap, type, change device settings and manage apps."
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: AgentAccess, rhs: AgentAccess) -> Bool { lhs.rank < rhs.rank }
}

/// Settings shared by the app and the MCP server process. Both read the app's preferences domain
/// explicitly, so the server sees a change the moment the user makes it.
enum AgentSettings {
    /// The app's bundle id, which is also its preferences domain.
    static let domainName = "se.royan.ohmyandroid"
    private static var domain: CFString { domainName as CFString }
    static let accessKey = "agents.access"
    static let lastClientKey = "agents.lastClient"
    static let lastUsedKey = "agents.lastUsed"
    /// Device selected in the panel; the server's default when several devices are connected.
    static let panelDeviceKey = "device.lastSerial"
    static let defaultAccess = AgentAccess.full

    static var access: AgentAccess {
        CFPreferencesAppSynchronize(domain)
        let raw = CFPreferencesCopyAppValue(accessKey as CFString, domain) as? String
        return raw.flatMap(AgentAccess.init) ?? defaultAccess
    }

    static var panelDevice: String? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(panelDeviceKey as CFString, domain) as? String
    }

    /// Written by the server so Settings can show that the connection works.
    static func recordUse(client: String?) {
        CFPreferencesSetAppValue(lastUsedKey as CFString, Date() as CFDate, domain)
        if let client { CFPreferencesSetAppValue(lastClientKey as CFString, client as CFString, domain) }
        CFPreferencesAppSynchronize(domain)
    }

    static var lastUse: (date: Date, client: String?)? {
        CFPreferencesAppSynchronize(domain)
        guard let date = CFPreferencesCopyAppValue(lastUsedKey as CFString, domain) as? Date else { return nil }
        return (date, CFPreferencesCopyAppValue(lastClientKey as CFString, domain) as? String)
    }
}
