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
            let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let total = Int(try query(db, "SELECT COUNT(*) FROM \(quoted)").rows.first?.cells.first ?? "0") ?? 0
            let result = try query(db, "SELECT * FROM \(quoted) LIMIT \(pageSize) OFFSET \(offset)")
            return TablePage(columns: result.columns, rows: result.rows, totalRows: total)
        }
    }

    // MARK: - Private

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

    private static func query(_ db: OpaquePointer, _ sql: String) throws -> (columns: [String], rows: [TableRow]) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppError("SQLite: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        let count = Int(sqlite3_column_count(statement))
        let columns = (0..<count).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
        var rows: [TableRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
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
        return (columns, rows)
    }
}
