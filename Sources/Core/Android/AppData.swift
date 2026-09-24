import Foundation

struct PreferenceEntry: Identifiable, Hashable, Sendable {
    let key: String
    let type: String
    let value: String
    var id: String { key }
}

/// Read-only access to an app's private storage. Uses `run-as`, which Android grants for debuggable
/// builds only — the same door Android Studio's inspectors use. Release apps stay closed, by design.
protocol AppDataReading: Sendable {
    func debuggablePackages(on device: Device, adb: ADBClient) async throws -> [String]
    func preferenceFiles(of package: String, on device: Device, adb: ADBClient) async throws -> [String]
    func preferences(of package: String, file: String, on device: Device, adb: ADBClient) async throws -> [PreferenceEntry]
    func databaseFiles(of package: String, on device: Device, adb: ADBClient) async throws -> [String]
    /// Copies the database (with its WAL and SHM side files when present) to a local temporary file.
    func pullDatabase(of package: String, name: String, on device: Device, adb: ADBClient) async throws -> URL
}

struct RunAsAppDataReader: AppDataReading {
    func debuggablePackages(on device: Device, adb: ADBClient) async throws -> [String] {
        let script = "for p in $(pm list packages -3 | cut -d: -f2); do run-as $p id >/dev/null 2>&1 && echo $p; done"
        return try await adb.shell(device, script).split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }.sorted()
    }

    func preferenceFiles(of package: String, on device: Device, adb: ADBClient) async throws -> [String] {
        try await list("shared_prefs", of: package, on: device, adb: adb).filter { $0.hasSuffix(".xml") }
    }

    func preferences(of package: String, file: String, on device: Device, adb: ADBClient) async throws -> [PreferenceEntry] {
        let xml = try await adb.execOut(device, "run-as \(package) cat shared_prefs/\(file.shellQuoted)")
        return PreferencesXMLParser.parse(xml)
    }

    func databaseFiles(of package: String, on device: Device, adb: ADBClient) async throws -> [String] {
        try await list("databases", of: package, on: device, adb: adb).filter { name in
            !name.hasSuffix("-journal") && !name.hasSuffix("-wal") && !name.hasSuffix("-shm")
        }
    }

    func pullDatabase(of package: String, name: String, on device: Device, adb: ADBClient) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "oyama-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let local = directory.appending(path: name)
        try await adb.execOut(device, "run-as \(package) cat databases/\(name.shellQuoted)").write(to: local)
        for suffix in ["-wal", "-shm"] {
            guard let data = try? await adb.execOut(device, "run-as \(package) cat databases/\((name + suffix).shellQuoted)"),
                  Self.looksLikeSQLiteSideFile(data, suffix: suffix) else { continue }
            try data.write(to: directory.appending(path: name + suffix))
        }
        return local
    }

    /// A failed `cat` can print its error to stdout; only keep real side files (WAL magic 0x377f068x, SHM header).
    private static func looksLikeSQLiteSideFile(_ data: Data, suffix: String) -> Bool {
        guard data.count >= 32 else { return false }
        return suffix == "-wal" ? data.prefix(3) == Data([0x37, 0x7f, 0x06]) : true
    }

    private func list(_ directory: String, of package: String, on device: Device, adb: ADBClient) async throws -> [String] {
        let output = (try? await adb.shell(device, "run-as \(package) ls -1 \(directory) 2>/dev/null")) ?? ""
        return output.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }.sorted()
    }
}

/// Parses Android's SharedPreferences XML (`<map>` of typed elements).
private final class PreferencesXMLParser: NSObject, XMLParserDelegate {
    private var entries: [PreferenceEntry] = []
    private var current: (key: String, type: String)?
    private var text = ""
    private var setItems: [String] = []

    static func parse(_ data: Data) -> [PreferenceEntry] {
        let delegate = PreferencesXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "map" { return }
        if let name = attributes["name"] {
            current = (name, element)
            text = ""
            setItems = []
            if let value = attributes["value"] { entries.append(PreferenceEntry(key: name, type: element, value: value)) }
        } else if element == "string", current?.type == "set" {
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        guard let current else { return }
        switch element {
        case "string" where current.type == "set":
            setItems.append(text)
        case "string":
            entries.append(PreferenceEntry(key: current.key, type: "string", value: text))
            self.current = nil
        case "set":
            entries.append(PreferenceEntry(key: current.key, type: "set", value: setItems.joined(separator: ", ")))
            self.current = nil
        case "map":
            break
        default:
            if current.type == element { self.current = nil }
        }
    }
}
