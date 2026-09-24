import Foundation
import SQLite3

struct TableRow: Identifiable, Hashable, Sendable {
    let id: Int
    let cells: [String]

    /// Column count can briefly disagree with the row while the table switches; never trap on it.
    func cell(_ index: Int) -> String { cells.indices.contains(index) ? cells[index] : "" }
}

struct TablePage: Sendable {
    let columns: [String]
    let rows: [TableRow]
    let totalRows: Int
}

/// Read-only queries against a local copy of a database. Opens, reads, closes; no handle outlives a call.
enum SQLiteSnapshot {
    static let pageSize = 500

    static func tables(at url: URL) throws -> [String] {
        try withDatabase(url) { db in
            try query(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").rows.map { $0.cells[0] }
        }
    }

    static func page(of table: String, at url: URL, offset: Int = 0) throws -> TablePage {
        try withDatabase(url) { db in
            let total = Int(try query(db, "SELECT COUNT(*) FROM \(quoted(table))").rows.first?.cells.first ?? "0") ?? 0
            let result = try query(db, "SELECT * FROM \(quoted(table)) LIMIT \(pageSize) OFFSET \(offset)")
            return TablePage(columns: result.columns, rows: result.rows, totalRows: total)
        }
    }

    struct SchemaEntry: Sendable {
        let name: String
        let sql: String
        /// Row count for tables; nil for indexes and views.
        let rows: Int?
    }

    /// `CREATE` statements of tables, views and indexes, with the row count of each table.
    static func schema(at url: URL) throws -> [SchemaEntry] {
        try withDatabase(url) { db in
            let result = try query(db, "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type = 'index', name")
            return try result.rows.map { row in
                let rows = row.cell(0) == "table" ? Int(try query(db, "SELECT COUNT(*) FROM \(quoted(row.cell(1)))").rows.first?.cell(0) ?? "") : nil
                return SchemaEntry(name: row.cell(1), sql: row.cell(2), rows: rows)
            }
        }
    }

    struct QueryResult: Sendable {
        let columns: [String]
        let rows: [TableRow]
        /// More rows exist beyond `limit`.
        let truncated: Bool
    }

    /// Runs one statement that only reads. Writes are refused twice: by `PRAGMA query_only` and by
    /// SQLite's own read-only check of the prepared statement. The file is a copy in any case.
    static func run(_ sql: String, at url: URL, limit: Int) throws -> QueryResult {
        try withDatabase(url) { db in
            sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil)
            let result = try query(db, sql, limit: limit, readOnly: true)
            return QueryResult(columns: result.columns, rows: result.rows, truncated: result.truncated)
        }
    }

    // MARK: - Private

    private static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func withDatabase<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw AppError("SQLite: \(message)")
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func query(
        _ db: OpaquePointer, _ sql: String, limit: Int = .max, readOnly: Bool = false
    ) throws -> (columns: [String], rows: [TableRow], truncated: Bool) {
        var statement: OpaquePointer?
        // The tail points into the C string, so it is read inside `withCString`.
        let remainder = sql.withCString { text -> String? in
            var tail: UnsafePointer<CChar>?
            guard sqlite3_prepare_v2(db, text, -1, &statement, &tail) == SQLITE_OK else { return nil }
            return tail.map { String(cString: $0) } ?? ""
        }
        guard let remainder, let statement else { throw AppError("SQLite: \(String(cString: sqlite3_errmsg(db)))") }
        defer { sqlite3_finalize(statement) }
        if readOnly {
            guard sqlite3_stmt_readonly(statement) != 0 else { throw AppError("Only statements that read are allowed (SELECT, PRAGMA, WITH).") }
            guard remainder.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union([";"])).isEmpty else {
                throw AppError("Run one statement at a time.")
            }
        }
        let count = Int(sqlite3_column_count(statement))
        let columns = (0..<count).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
        var rows: [TableRow] = []
        var truncated = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard rows.count < limit else { truncated = true; break }
            let cells = (0..<count).map { column -> String in
                let index = Int32(column)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_NULL: return "NULL"
                case SQLITE_INTEGER: return String(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: return String(sqlite3_column_double(statement, index))
                case SQLITE_BLOB: return "<blob \(sqlite3_column_bytes(statement, index)) B>"
                default: return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
                }
            }
            rows.append(TableRow(id: rows.count, cells: cells))
        }
        return (columns, rows, truncated)
    }
}
