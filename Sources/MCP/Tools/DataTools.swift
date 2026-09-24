import Foundation

/// Private data of debuggable apps, read-only: SharedPreferences and SQLite (Room) databases.
enum DataTools {
    static let all = [readPreferences, queryDatabase]
    static let maxCell = 200

    static let readPreferences = Tool(
        name: "read_preferences",
        title: "Read preferences",
        description: "SharedPreferences of a debuggable app: key (type) = value, per file. Default: the app on screen.",
        effect: .read,
        parameters: [
            .string("package", "App. Default: the app on screen."),
            .string("file", "One file, e.g. settings.xml. Default: all files."),
        ]
    ) { call in
        let context = try await call.device()
        let package = try await call.debuggablePackage(context)
        let reader = call.environment.appData
        var files = try await reader.preferenceFiles(of: package, on: context.device, adb: context.adb)
        if let file = try call.arguments.string("file") {
            let name = try safeFileName(file.hasSuffix(".xml") ? file : file + ".xml")
            guard files.contains(name) else { throw ToolInputError("No \(name). Files: \(files.joined(separator: ", ")).") }
            files = [name]
        }
        guard !files.isEmpty else { return .text("\(package) has no SharedPreferences files.") }
        var lines: [String] = []
        for file in files {
            lines.append("\(file):")
            let entries = try await reader.preferences(of: package, file: file, on: context.device, adb: context.adb)
            lines += entries.isEmpty ? ["  (empty)"] : entries.map { "  \($0.key) (\($0.type)) = \(clip($0.value))" }
        }
        return .text(lines.joined(separator: "\n"))
    }

    static let queryDatabase = Tool(
        name: "query_database",
        title: "Query database",
        description: """
        SQLite databases of a debuggable app, read-only on a fresh copy. No database: lists databases and tables. \
        database only: schema and row counts. With sql: runs one SELECT/PRAGMA/WITH and returns tab-separated rows.
        """,
        effect: .read,
        parameters: [
            .string("package", "App. Default: the app on screen."),
            .string("database", "Database file name from the list, e.g. app.db."),
            .string("sql", "One read-only statement."),
            .integer("limit", "Maximum rows. Default 50.", range: 1...500),
        ]
    ) { call in
        let context = try await call.device()
        let package = try await call.debuggablePackage(context)
        let reader = call.environment.appData
        let names = try await reader.databaseFiles(of: package, on: context.device, adb: context.adb)
        guard !names.isEmpty else { return .text("\(package) has no databases.") }

        guard let database = try call.arguments.string("database").map(safeFileName) else {
            var lines: [String] = []
            for name in names {
                let schema = try await withCopy(package, name, call, context) { try SQLiteSnapshot.schema(at: $0) }
                let tables = schema.compactMap { entry in entry.rows.map { "\(entry.name) (\($0))" } }
                lines.append("\(name): \(tables.isEmpty ? "no tables" : tables.joined(separator: ", "))")
            }
            return .text(lines.joined(separator: "\n"))
        }
        guard names.contains(database) else { throw ToolInputError("No \(database). Databases: \(names.joined(separator: ", ")).") }

        guard let sql = try call.arguments.string("sql")?.trimmed, !sql.isEmpty else {
            let schema = try await withCopy(package, database, call, context) { try SQLiteSnapshot.schema(at: $0) }
            return .text(schema.map { entry in entry.rows.map { "-- \($0) rows\n" + entry.sql + ";" } ?? entry.sql + ";" }.joined(separator: "\n"))
        }
        let limit = try call.arguments.int("limit", in: 1...500) ?? 50
        let result = try await withCopy(package, database, call, context) { try SQLiteSnapshot.run(sql, at: $0, limit: limit) }
        var lines = [result.columns.joined(separator: "\t")]
        lines += result.rows.map { row in row.cells.map { clip($0).replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t") }
        lines.append(result.truncated ? "(first \(limit) rows; raise limit or narrow the query)" : "(\(result.rows.count) rows)")
        return .text(lines.joined(separator: "\n"))
    }

    /// Pulls a fresh copy, runs the read off the caller's task, and always deletes the copy: it holds private app data.
    private static func withCopy<T: Sendable>(
        _ package: String, _ name: String, _ call: ToolCall, _ context: DeviceContext, _ read: @escaping @Sendable (URL) throws -> T
    ) async throws -> T {
        let url = try await call.environment.appData.pullDatabase(of: package, name: name, on: context.device, adb: context.adb)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try await Task.detached { try read(url) }.value
    }

    /// Names become local paths; refuse anything that could leave the temporary folder.
    private static func safeFileName(_ name: String) throws -> String {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw ToolInputError("Give a file name, not a path.") }
        return name
    }

    private static func clip(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\n", with: "\\n")
        return flat.count > maxCell ? flat.prefix(maxCell) + "…" : flat
    }
}

private extension ToolCall {
    /// Target package, checked for `run-as` access so the model gets a clear reason instead of empty lists.
    func debuggablePackage(_ context: DeviceContext) async throws -> String {
        let package = try await package(context)
        guard (try? await context.shell("run-as \(package) true && echo ok").trimmed) == "ok" else {
            throw AppError("\(package) is not debuggable (or not installed). App data needs a debug build; list_apps marks debuggable apps.")
        }
        return package
    }
}
