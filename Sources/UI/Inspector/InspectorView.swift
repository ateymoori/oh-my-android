import SwiftUI

/// Read-only browser for an app's SharedPreferences and SQLite databases.
struct InspectorView: View {
    @Bindable var store: InspectorStore
    @State private var search = ""

    var body: some View {
        Group {
            if store.packages.isEmpty, !store.isLoading {
                ContentUnavailableView(
                    "No debuggable apps",
                    systemImage: "lock",
                    description: Text("run-as only opens apps built with debuggable = true. Install a debug build of your app.")
                )
            } else {
                switch store.section {
                case .preferences: PreferencesPane(store: store, search: $search)
                case .databases: DatabasePane(store: store, search: $search)
                }
            }
        }
        .frame(minWidth: 880, idealWidth: 980, minHeight: 440, idealHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("App", selection: $store.selectedPackage) {
                    ForEach(store.packages, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(minWidth: 220)
                .help("Debuggable app to inspect")
            }
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $store.section) {
                    ForEach(InspectorStore.Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Preferences: SharedPreferences XML. Databases: SQLite tables.")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isLoading { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Reload from the device (⌘R). Read-only: nothing is written to the device.")
            }
        }
        .overlay(alignment: .bottom) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).padding(8).glassEffect(.regular, in: .capsule).padding()
            }
        }
    }
}

private struct PreferencesPane: View {
    @Bindable var store: InspectorStore
    @Binding var search: String

    private var entries: [PreferenceEntry] {
        guard !search.isEmpty else { return store.preferences }
        return store.preferences.filter { $0.key.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(store.preferenceFiles, id: \.self, selection: $store.selectedPreferenceFile) { file in
                Label(file.replacingOccurrences(of: ".xml", with: ""), systemImage: "doc.text")
            }
            .overlay { if store.preferenceFiles.isEmpty { ContentUnavailableView("No preference files", systemImage: "doc.text") } }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            Table(entries) {
                TableColumn("Key", value: \.key).width(min: 120, ideal: 240)
                TableColumn("Type", value: \.type).width(60)
                TableColumn("Value") { entry in
                    Text(entry.value).textSelection(.enabled).help(entry.value)
                }
            }
            .overlay { if entries.isEmpty { ContentUnavailableView.search(text: search) } }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter keys and values")
    }
}

private struct DatabasePane: View {
    @Bindable var store: InspectorStore
    @Binding var search: String

    private var rows: [TableRow] {
        guard let page = store.page else { return [] }
        guard !search.isEmpty else { return page.rows }
        return page.rows.filter { row in row.cells.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedTable) {
                ForEach(store.databases) { database in
                    Section(database.file) {
                        ForEach(database.tables, id: \.self) { table in
                            Label(table, systemImage: "tablecells").tag(InspectorStore.TableSelection(file: database.file, table: table))
                        }
                    }
                }
            }
            .overlay { if store.databases.isEmpty { ContentUnavailableView("No databases", systemImage: "cylinder") } }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            if let page = store.page {
                VStack(spacing: 0) {
                    Table(rows) {
                        TableColumnForEach(Array(page.columns.enumerated()), id: \.offset) { column in
                            TableColumn(column.element) { (row: TableRow) in
                                let cell = row.cell(column.offset)
                                Text(cell).textSelection(.enabled).help(cell)
                            }
                        }
                    }
                    .id(store.selectedTable)  // columns differ per table: rebuild instead of diffing
                    .overlay { if rows.isEmpty, !search.isEmpty { ContentUnavailableView.search(text: search) } }
                    Divider()
                    Text(page.totalRows > SQLiteSnapshot.pageSize
                         ? "Showing first \(SQLiteSnapshot.pageSize) of \(page.totalRows) rows"
                         : "\(page.totalRows) \(page.totalRows == 1 ? "row" : "rows")")
                        .font(.caption).foregroundStyle(.secondary).padding(6)
                }
            } else {
                ContentUnavailableView("No table selected", systemImage: "tablecells")
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter rows")
    }
}
