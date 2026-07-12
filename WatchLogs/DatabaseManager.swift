//
//  DatabaseManager.swift
//  WatchLogs
//
//  Created by AD on 7/11/26.
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct RecentSessionSummary: Identifiable {
    let id: String
    let title: String
    let bundleID: String
    let startedAt: Date
    let endedAt: Date?
    let durationSec: Double
}

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let minimumSegmentLength: Double = 0.25

    private init() {
        openDatabase()
        createTablesIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    func startSession(
        id: UUID,
        title: String,
        bundleID: String,
        startedAt: Date,
        durationTotal: Double?
    ) {
        let sql = """
        INSERT OR REPLACE INTO sessions (id, title, bundle_id, started_at, ended_at, duration_sec, duration_total)
        VALUES (?, ?, ?, ?, NULL, 0, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(id.uuidString, to: stmt, at: 1)
        bindText(title, to: stmt, at: 2)
        bindText(bundleID, to: stmt, at: 3)
        sqlite3_bind_double(stmt, 4, startedAt.timeIntervalSince1970)

        if let durationTotal {
            sqlite3_bind_double(stmt, 5, durationTotal)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        sqlite3_step(stmt)
    }

    func addSegment(sessionID: UUID, startSec: Double, endSec: Double) {
        guard endSec - startSec >= minimumSegmentLength else { return }

        let sql = """
        INSERT INTO watched_segments (session_id, start_sec, end_sec, created_at)
        VALUES (?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(sessionID.uuidString, to: stmt, at: 1)
        sqlite3_bind_double(stmt, 2, startSec)
        sqlite3_bind_double(stmt, 3, endSec)
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)

        sqlite3_step(stmt)

        let merged = recomputeSessionDuration(sessionID: sessionID)
        let updateSQL = "UPDATE sessions SET duration_sec = ? WHERE id = ?;"
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }

        sqlite3_bind_double(updateStmt, 1, merged)
        bindText(sessionID.uuidString, to: updateStmt, at: 2)
        sqlite3_step(updateStmt)
    }

    func endSession(sessionID: UUID, endedAt: Date) {
        let merged = recomputeSessionDuration(sessionID: sessionID)

        let sql = """
        UPDATE sessions
        SET ended_at = ?, duration_sec = ?
        WHERE id = ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, endedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, merged)
        bindText(sessionID.uuidString, to: stmt, at: 3)

        sqlite3_step(stmt)
    }

    func todayTotalSeconds(now: Date = Date()) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now).timeIntervalSince1970
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!.timeIntervalSince1970

        let sql = """
        SELECT COALESCE(SUM(duration_sec), 0)
        FROM sessions
        WHERE started_at >= ? AND started_at < ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, startOfDay)
        sqlite3_bind_double(stmt, 2, startOfNextDay)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_double(stmt, 0)
        }

        return 0
    }

    func recentSessions(limit: Int = 20) -> [RecentSessionSummary] {
        let sql = """
        SELECT id, title, bundle_id, started_at, ended_at, duration_sec
        FROM sessions
        ORDER BY started_at DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var rows: [RecentSessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let titlePtr = sqlite3_column_text(stmt, 1),
                  let bundlePtr = sqlite3_column_text(stmt, 2)
            else { continue }

            let id = String(cString: idPtr)
            let title = String(cString: titlePtr)
            let bundleID = String(cString: bundlePtr)
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

            let endedAt: Date?
            if sqlite3_column_type(stmt, 4) == SQLITE_NULL {
                endedAt = nil
            } else {
                endedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            }

            let durationSec = sqlite3_column_double(stmt, 5)

            rows.append(
                RecentSessionSummary(
                    id: id,
                    title: title,
                    bundleID: bundleID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSec: durationSec
                )
            )
        }

        return rows
    }

    private func recomputeSessionDuration(sessionID: UUID) -> Double {
        let sql = """
        SELECT start_sec, end_sec
        FROM watched_segments
        WHERE session_id = ?
        ORDER BY start_sec ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        bindText(sessionID.uuidString, to: stmt, at: 1)

        var ranges: [(Double, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let start = sqlite3_column_double(stmt, 0)
            let end = sqlite3_column_double(stmt, 1)
            if end > start { ranges.append((start, end)) }
        }

        guard !ranges.isEmpty else { return 0 }

        var merged: [(Double, Double)] = [ranges[0]]
        for range in ranges.dropFirst() {
            let last = merged[merged.count - 1]
            if range.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, range.1))
            } else {
                merged.append(range)
            }
        }

        return merged.reduce(0) { partial, range in
            partial + (range.1 - range.0)
        }
    }

    private func openDatabase() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WatchLogs", isDirectory: true)

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbURL = dir.appendingPathComponent("watchlogs.sqlite")
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("DatabaseManager: failed to open database at \(dbURL.path)")
            return
        }

        _ = execute("PRAGMA foreign_keys = ON;")
    }

    private func createTablesIfNeeded() {
        let createSessions = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL,
            duration_sec REAL NOT NULL DEFAULT 0,
            duration_total REAL
        );
        """

        let createSegments = """
        CREATE TABLE IF NOT EXISTS watched_segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            start_sec REAL NOT NULL,
            end_sec REAL NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """

        let indexSegments = """
        CREATE INDEX IF NOT EXISTS idx_watched_segments_session_id
        ON watched_segments(session_id);
        """

        let indexSessions = """
        CREATE INDEX IF NOT EXISTS idx_sessions_started_at
        ON sessions(started_at);
        """

        _ = execute(createSessions)
        _ = execute(createSegments)
        _ = execute(indexSegments)
        _ = execute(indexSessions)
    }

    private func bindText(_ value: String, to stmt: OpaquePointer?, at index: Int32) {
        _ = value.withCString { ptr in
            sqlite3_bind_text(stmt, index, ptr, -1, SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            if let error {
                print("DatabaseManager SQL error: \(String(cString: error))")
                sqlite3_free(error)
            }
            return false
        }
        return true
    }
}
