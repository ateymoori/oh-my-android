import Foundation
import Observation

/// State of the Data Inspector window: which app, which store, what is shown.
@MainActor
@Observable
final class InspectorStore {
    enum Section: String, CaseIterable, Identifiable {
        case preferences = "Preferences"
        case databases = "Databases"
        var id: String { rawValue }
    }

    struct DatabaseEntry: Identifiable, Hashable {
        let file: String
        let tables: [String]
        var id: String { file }
    }

    struct TableSelection: Hashable {
        let file: String
        let table: String
    }

    private(set) var packages: [String] = []
    var selectedPackage: String? { didSet { if selectedPackage != oldValue { Task { await loadFiles() } } } }
    var section: Section = Section(rawValue: UserDefaults.standard.string(forKey: InspectorStore.sectionKey) ?? "") ?? .preferences {
        didSet {
            guard section != oldValue else { return }
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey)
            Task { await loadFiles() }
        }
    }

    private(set) var preferenceFiles: [String] = []
    var selectedPreferenceFile: String? { didSet { if selectedPreferenceFile != oldValue { Task { await loadPreferences() } } } }
    private(set) var preferences: [PreferenceEntry] = []

    private(set) var databases: [DatabaseEntry] = []
    var selectedTable: TableSelection? { didSet { if selectedTable != oldValue { Task { await loadPage() } } } }
    private(set) var page: TablePage?

    private var activeLoads = 0
    var isLoading: Bool { activeLoads > 0 }
    private(set) var error: String?

    private static let sectionKey = "inspector.section"
    private let reader: AppDataReading
    private var context: DeviceContext?
    private var localDatabases: [String: URL] = [:]

    init(reader: AppDataReading) {
        self.reader = reader
    }

    /// Lists debuggable apps and pre-selects the one on screen when it is debuggable.
    func open(_ context: DeviceContext) async {
        self.context = context
        await load { [reader] in
            let foreground = try? await context.foreground.package(on: context.device, adb: context.adb)
            let packages = try await reader.debuggablePackages(on: context.device, adb: context.adb)
            self.packages = packages
            let preferred = [foreground, self.selectedPackage, packages.first].compactMap { $0 }.first { packages.contains($0) }
            if preferred == self.selectedPackage { await self.loadFiles() } else { self.selectedPackage = preferred }
        }
    }

    func refresh() async {
        guard let context else { return }
        await open(context)
    }

    // MARK: - Loading

    private func loadFiles() async {
        guard let context, let package = selectedPackage else { return }
        let section = section
        // Selection may change while adb works; results for an old selection are dropped.
        let isCurrent = { [weak self] in self?.selectedPackage == package && self?.section == section }
        switch section {
        case .preferences:
            await load { [reader] in
                let files = try await reader.preferenceFiles(of: package, on: context.device, adb: context.adb)
                guard isCurrent() else { return }
                self.preferenceFiles = files
                let keep = self.selectedPreferenceFile.map(files.contains) ?? false
                if keep { await self.loadPreferences() } else { self.selectedPreferenceFile = files.first }
                if files.isEmpty { self.preferences = [] }
            }
        case .databases:
            await load { [reader] in
                var pulled: [String: URL] = [:]
                var entries: [DatabaseEntry] = []
                do {
                    for file in try await reader.databaseFiles(of: package, on: context.device, adb: context.adb) {
                        let url = try await reader.pullDatabase(of: package, name: file, on: context.device, adb: context.adb)
                        pulled[file] = url
                        entries.append(DatabaseEntry(file: file, tables: try await Task.detached { try SQLiteSnapshot.tables(at: url) }.value))
                    }
                } catch {
                    Self.remove(pulled)
                    throw error
                }
                guard isCurrent() else { return Self.remove(pulled) }
                self.discardLocalDatabases()
                self.localDatabases = pulled
                self.databases = entries
                let keep = self.selectedTable.map { selection in entries.contains { $0.file == selection.file && $0.tables.contains(selection.table) } } ?? false
                if keep {
                    await self.loadPage()
                } else {
                    self.selectedTable = entries.lazy.flatMap { entry in entry.tables.map { TableSelection(file: entry.file, table: $0) } }.first
                }
                if entries.isEmpty { self.page = nil }
            }
        }
    }

    private func loadPreferences() async {
        guard let context, let package = selectedPackage, let file = selectedPreferenceFile else { return }
        await load { [reader] in
            let entries = try await reader.preferences(of: package, file: file, on: context.device, adb: context.adb)
            guard self.selectedPackage == package, self.selectedPreferenceFile == file else { return }
            self.preferences = entries
        }
    }

    private func loadPage() async {
        guard let selection = selectedTable, let url = localDatabases[selection.file] else { return }
        await load {
            let page = try await Task.detached { try SQLiteSnapshot.page(of: selection.table, at: url) }.value
            guard self.selectedTable == selection else { return }
            self.page = page
        }
    }

    /// Pulled copies hold private app data; they live in a temporary folder per database and are deleted
    /// before pulling again and when the app quits.
    func discardLocalDatabases() {
        Self.remove(localDatabases)
        localDatabases = [:]
    }

    private static func remove(_ databases: [String: URL]) {
        for url in databases.values { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    private func load(_ work: @escaping @MainActor () async throws -> Void) async {
        activeLoads += 1
        error = nil
        do { try await work() } catch { self.error = error.localizedDescription }
        activeLoads -= 1
    }
}
