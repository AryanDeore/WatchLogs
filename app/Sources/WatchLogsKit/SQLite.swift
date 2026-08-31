import Foundation
import SQLite3

/// A hand-rolled, synchronous wrapper over the system `sqlite3` C API — enough
/// for the App's one connection, no third-party dependency.
///
/// Every call is blocking and must happen on whatever thread the caller is on;
/// `EventStore` owns the only instance and serialises access behind its own
/// lock, matching the server's "one request in flight at a time".
final class SQLiteDatabase {
    /// A bindable parameter. Deliberately tiny: these are the only JSON types
    /// the Flush schema carries.
    enum Value {
        case int(Int)
        case double(Double)
        case text(String)
        case null

        static func optionalDouble(_ value: Double?) -> Value { value.map(Value.double) ?? .null }
        static func optionalText(_ value: String?) -> Value { value.map(Value.text) ?? .null }
        static func bool(_ value: Bool) -> Value { .int(value ? 1 : 0) }
        static func optionalBool(_ value: Bool?) -> Value { value.map(Value.bool) ?? .null }
    }

    /// One result row, addressed by column index.
    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
        func text(_ index: Int32) -> String {
            guard let cString = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: cString)
        }

        func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }
        func optionalInt(_ index: Int32) -> Int? { isNull(index) ? nil : int(index) }
        func optionalDouble(_ index: Int32) -> Double? {
            isNull(index) ? nil : sqlite3_column_double(statement, index)
        }
        func optionalText(_ index: Int32) -> String? { isNull(index) ? nil : text(index) }
        func bool(_ index: Int32) -> Bool { int(index) != 0 }
    }

    private var handle: OpaquePointer?

    /// `path` may be a filesystem path or `":memory:"` (what the tests use, so
    /// they exercise the real SQL).
    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, handle != nil else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(path)"
            sqlite3_close(handle)
            throw SQLiteError.open(message)
        }
        self.handle = handle
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    /// Run one or more statements with no parameters and no results (schema DDL).
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteError.statement(message, sql: sql)
        }
    }

    /// Run a parameterised statement that returns nothing.
    func run(_ sql: String, _ parameters: [Value] = []) throws {
        try query(sql, parameters) { _ in }
    }

    /// Run a parameterised query, calling `row` once per result row.
    func query(_ sql: String, _ parameters: [Value] = [], row consume: (Row) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.statement(String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch parameter {
            case .int(let value): result = sqlite3_bind_int64(statement, index, Int64(value))
            case .double(let value): result = sqlite3_bind_double(statement, index, value)
            case .text(let value): result = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw SQLiteError.statement(String(cString: sqlite3_errmsg(handle)), sql: sql)
            }
        }

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: consume(Row(statement: statement))
            case SQLITE_DONE: return
            default: throw SQLiteError.statement(String(cString: sqlite3_errmsg(handle)), sql: sql)
            }
        }
    }

    /// Run `body` inside a transaction, rolling back if it throws. A Flush is
    /// recorded and its Views recomputed in one of these, so a crash mid-Flush
    /// never leaves Segments derived from half a batch.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// SQLite must copy bound strings: the Swift `String` bridging buffer is
    /// gone by the time the statement runs.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum SQLiteError: Error, Equatable {
    case open(String)
    case statement(String, sql: String)
}
