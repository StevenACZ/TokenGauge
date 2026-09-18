import Darwin
import Foundation
import SQLite3

struct SQLiteStatement {
    let handle: OpaquePointer

    private static var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(Int(-1), to: sqlite3_destructor_type.self)
    }

    func bind(_ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(handle, index)
            return
        }
        sqlite3_bind_text(handle, index, value, -1, Self.transientDestructor)
    }

    func bind(_ index: Int32, _ value: Int64?) {
        guard let value else {
            sqlite3_bind_null(handle, index)
            return
        }
        sqlite3_bind_int64(handle, index, value)
    }

    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(handle, index, value)
    }

    func bind(_ index: Int32, _ value: Bool) {
        sqlite3_bind_int(handle, index, value ? 1 : 0)
    }

    func bind(_ index: Int32, _ value: Date?) {
        guard let value else {
            sqlite3_bind_null(handle, index)
            return
        }
        sqlite3_bind_double(handle, index, value.timeIntervalSince1970)
    }

    func text(_ index: Int32) -> String {
        optionalText(index) ?? ""
    }

    func optionalText(_ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: raw)
    }

    func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(handle, index))
    }

    func optionalInt(_ index: Int32) -> Int? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(handle, index))
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    func flag(_ index: Int32) -> Bool {
        sqlite3_column_int(handle, index) == 1
    }

    func date(_ index: Int32) -> Date? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(handle, index))
    }

    func instant(_ index: Int32) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(handle, index))
    }
}

final class SQLiteConnection {
    private let handle: OpaquePointer

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    var isReadOnly: Bool {
        sqlite3_db_readonly(handle, "main") == 1
    }

    static func open(_ url: URL, readOnly: Bool) throws -> SQLiteConnection {
        if !readOnly {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        var handle: OpaquePointer?
        let flags =
            readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? url.path
            if let handle { sqlite3_close(handle) }
            throw UsageHistoryError.openFailed(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
        if !readOnly { chmod(url.path, S_IRUSR | S_IWUSR) }
        return SQLiteConnection(handle: handle)
    }

    func close() {
        sqlite3_close_v2(handle)
    }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? sql
            sqlite3_free(error)
            throw UsageHistoryError.statementFailed(message)
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func run(_ sql: String, bindings: (SQLiteStatement) -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        bindings(statement)
        guard sqlite3_step(statement.handle) == SQLITE_DONE else {
            throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func query(
        _ sql: String,
        bindings: (SQLiteStatement) -> Void,
        each: (SQLiteStatement) -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        bindings(statement)
        while true {
            switch sqlite3_step(statement.handle) {
            case SQLITE_ROW: each(statement)
            case SQLITE_DONE: return
            default: throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
        return SQLiteStatement(handle: statement)
    }
}
