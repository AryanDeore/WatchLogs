import Foundation

/// The App's storage: the append-only raw Event log, the Segments derived from
/// it, and the read model the UI asks for totals.
///
/// Two things go in and out of here, which is the whole interface:
/// `record(_:serverTime:)` takes a decoded Flush and hands back its Ack, and
/// `totals(in:)` answers "how much Watched time in this window". Everything
/// between — de-duplication, the Segment state machine, replaying the Ack of a
/// Flush that arrived twice — is inside.
///
/// Recording a Flush and recomputing the Views it touched happen in one
/// transaction, so a crash mid-Flush never leaves Segments derived from half a
/// batch. All access is serialised behind one lock: the loopback server runs one
/// request at a time, and the menubar's reads are cheap.
public final class EventStore: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()
    private let schemaVersion: Int

    /// `path` is a filesystem path, or `":memory:"` for a database that lives and
    /// dies with the process (what the tests use, so they exercise the real SQL).
    ///
    /// `schemaVersion` is the version this instance computes `rollup_slice`
    /// rows under (ADR 0004) — injectable, like `Clock`, so a test can reopen
    /// a store on the same file under a bumped version and exercise the
    /// mismatch-triggers-a-rebuild path without waiting for a real code change.
    public init(path: String, schemaVersion: Int = EventStore.currentSchemaVersion) throws {
        database = try SQLiteDatabase(path: path)
        self.schemaVersion = schemaVersion
        try database.execute(Self.schema)
    }

    /// `~/Library/Application Support/WatchLogs/watchlogs.sqlite`, creating the
    /// directory if this is a first run.
    public static func defaultPath(fileManager: FileManager = .default) throws -> String {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("WatchLogs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("watchlogs.sqlite").path
    }

    // MARK: - Ingest

    /// Store a Flush and return the Ack for it.
    ///
    /// Delivery is at-least-once (ADR 0002): the Extension resends a batch whose
    /// Ack it never saw, reusing the same `flushId`. That resend stores nothing
    /// and replays the Ack from the first delivery verbatim — including its
    /// original `serverTime` — so no total moves. A batch that overlaps an
    /// earlier one under a *new* `flushId` is stored (the log is append-only and
    /// may hold the same Event twice) and de-duplicated on `(viewId, seq)` when
    /// Segments are recomputed.
    ///
    /// `ackSeq` is the highest `seq` the log holds for that View, not merely the
    /// highest in this batch, so the Extension prunes everything the App has.
    @discardableResult
    public func record(_ envelope: FlushEnvelope, serverTime: Int) throws -> Ack {
        lock.lock()
        defer { lock.unlock() }

        return try database.transaction {
            if let replayed = try storedAck(flushId: envelope.flushId) {
                return replayed
            }

            for view in envelope.views {
                try upsert(view)
                for event in view.events {
                    try append(event, to: view.viewId)
                }
            }

            var recomputed = Set<String>()
            for view in envelope.views where recomputed.insert(view.viewId).inserted {
                try recomputeSegments(viewId: view.viewId)
            }

            var viewAcks: [Ack.ViewAck] = []
            var acked = Set<String>()
            for view in envelope.views where acked.insert(view.viewId).inserted {
                viewAcks.append(Ack.ViewAck(viewId: view.viewId, ackSeq: try highestSeq(viewId: view.viewId)))
            }

            let ack = Ack(flushId: envelope.flushId, views: viewAcks, serverTime: serverTime)
            try database.run(
                "INSERT INTO flushes (flush_id, received_at_ms, ack_json) VALUES (?, ?, ?)",
                [.text(envelope.flushId), .int(serverTime), .text(String(decoding: ack.jsonData(), as: UTF8.self))]
            )
            try advanceOpenDay(now: Date(epochMillis: serverTime), calendar: .current)
            return ack
        }
    }

    // MARK: - Read model

    /// Watched and Background milliseconds in `range`.
    ///
    /// Segments are stored whole and clipped to the window here, at read time —
    /// a Segment that straddles the edge contributes only its overlap, and the
    /// stored Segment is never mutated.
    public func totals(in range: DateRange) throws -> Totals {
        lock.lock()
        defer { lock.unlock() }
        return try rawTotals(range: range)
    }

    // MARK: - The activity-flexed Day (ADR 0001) and the daily rollup cache (ADR 0004)

    /// The default an instance computes `rollup_slice` rows under unless a
    /// test overrides it. Bumping this marks every existing `rolled_day` row
    /// stale, so the next read repairs it (`reconcile`) with the new
    /// computation rather than needing a migration.
    public static let currentSchemaVersion = 1

    /// Watched and Background totals for `kind`, resolved against the
    /// activity-flexed Day (ADR 0001) rather than a naive calendar range.
    ///
    /// The sum of `slices(for:now:calendar:)` — see that method for how a
    /// Week/Month/Custom total is assembled from the rollup cache plus the
    /// live open Day.
    public func totals(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> Totals {
        lock.lock()
        defer { lock.unlock() }
        return try rawSlices(for: kind, now: now, calendar: calendar).reduce(into: Totals()) { totals, slice in
            totals.watchedMs += slice.totals.watchedMs
            totals.backgroundMs += slice.totals.backgroundMs
        }
    }

    /// Watched and Background totals for `kind`, one entry per `service ×
    /// contentFormat` combination present in the range (ADR 0004) — the full
    /// read model the By-Service pane (issue #7) reads.
    ///
    /// Advances and rolls up the open Day as far as `now` allows first, then
    /// repairs any rollup the reconciliation pass can now finish (a
    /// schema-version mismatch, or a Day a provisional Segment previously
    /// blocked). A range that includes the open Day sums the frozen rollup
    /// plus a live slice over `[openDayStart, now)` — the only part of the
    /// answer that is still provisional.
    public func slices(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> [TotalsSlice] {
        lock.lock()
        defer { lock.unlock() }
        return try rawSlices(for: kind, now: now, calendar: calendar)
    }

    /// Watched and Background totals for the live open Day only:
    /// `segments` clipped to `[openDayStart, now)`, never the rollup cache —
    /// the one part of any range that cannot be pre-aggregated (ADR 0004).
    public func openDayTotals(now: Date, calendar: Calendar = .current) throws -> Totals {
        lock.lock()
        defer { lock.unlock() }
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        return try rawTotals(range: DateRange(startMs: openStart.epochMillis, endMs: now.epochMillis))
    }

    /// The current open Day's start, or `nil` if the Day timeline has not
    /// bootstrapped yet (no Flush or read has ever landed).
    public func openDayStart() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return try openDayStartRaw()
    }

    /// Every fully processed frozen Day, oldest first — for inspecting freeze
    /// immutability. A Day the rollup job has not finished yet (still blocked
    /// on a provisional Segment) is not "processed" and does not appear here.
    public func frozenDays() throws -> [FrozenDay] {
        lock.lock()
        defer { lock.unlock() }
        return try loadFrozenDays()
    }

    /// The Day target hour (local, 0–23; default `04:00`, ADR 0001), a
    /// Settings control that takes effect for the open Day only.
    public func targetHour() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return try targetHourRaw()
    }

    /// `hour` is clamped to `0..<DayBoundary.hardCapHour`: the target hour
    /// must stay strictly before the fixed cap, or the cap (derived as an
    /// offset from the target hour) would stop acting as a same-day backstop.
    public func setTargetHour(_ hour: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(max(hour, 0), DayBoundary.hardCapHour - 1)
        try database.run(
            """
            INSERT INTO day_settings (id, target_hour) VALUES (1, ?)
            ON CONFLICT(id) DO UPDATE SET target_hour = excluded.target_hour
            """,
            [.int(clamped)]
        )
    }

    /// The manual "Rebuild statistics" Settings action (ADR 0004): drop both
    /// rollup tables and replay the Day-boundary walk over `segments` from
    /// scratch. Reproduces identical totals because `segments` — never the
    /// rollup cache — is the source of truth every rollup is derived from.
    public func rebuildStatistics(now: Date, calendar: Calendar = .current) throws {
        lock.lock()
        defer { lock.unlock() }
        try database.run("DELETE FROM rollup_slice")
        try database.run("DELETE FROM rolled_day")
        try rebuildFromSegments(now: now, calendar: calendar)
    }

    /// A View's Service/Adapter status (`CONTEXT.md` "Adapter"), or `nil` if
    /// no such View is stored. `nil` here means "unknown", never "no".
    public func needsAdapter(viewId: String) throws -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        var found: (service: String, adapterId: String?)?
        try database.query("SELECT service, adapter_id FROM views WHERE view_id = ?", [.text(viewId)]) { row in
            found = (row.text(0), row.optionalText(1))
        }
        guard let found else { return nil }
        return Adapter.needsAdapter(service: found.service, adapterId: found.adapterId)
    }

    /// Advance the open Day as far as `now` allows, resolve `kind` against it,
    /// and reconcile the rollup cache — the shared body behind `totals(for:)`
    /// and `slices(for:)`, run under one lock acquisition.
    private func rawSlices(for kind: DateRangeKind, now: Date, calendar: Calendar) throws -> [TotalsSlice] {
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        try reconcile(calendar: calendar)
        let resolved = try resolveRange(kind, openStart: openStart, calendar: calendar)
        var merged = try frozenSlices(startMs: resolved.startMs, endMs: resolved.endMs)
        if resolved.includesOpenDay {
            let live = try slicedTotals(startMs: openStart.epochMillis, endMs: now.epochMillis)
            merged = Self.merge(merged, live)
        }
        return merged.sorted { ($0.service, $0.contentFormat) < ($1.service, $1.contentFormat) }
    }

    private static func merge(_ a: [TotalsSlice], _ b: [TotalsSlice]) -> [TotalsSlice] {
        var byKey: [String: TotalsSlice] = [:]
        for slice in a + b {
            let key = "\(slice.service)\u{0}\(slice.contentFormat)"
            if var existing = byKey[key] {
                existing.totals.watchedMs += slice.totals.watchedMs
                existing.totals.backgroundMs += slice.totals.backgroundMs
                byKey[key] = existing
            } else {
                byKey[key] = slice
            }
        }
        return Array(byKey.values)
    }

    /// Freeze every Day whose boundary `now` confirms, starting from the
    /// current open Day, and return the (possibly advanced) open Day's start.
    /// Bootstraps the very first Day at `now` if the timeline has never
    /// started. Looping lets a long-closed App relaunch catch up through
    /// several empty Days in one pass rather than needing a background job.
    @discardableResult
    private func advanceOpenDay(now: Date, calendar: Calendar) throws -> Date {
        var start: Date
        if let existing = try openDayStartRaw() {
            start = existing
        } else {
            start = now
            try database.run("INSERT INTO open_day (id, day_start_ms) VALUES (1, ?)", [.int(start.epochMillis)])
        }

        let targetHour = try targetHourRaw()
        while let end = DayBoundary.confirmedEnd(
            dayStart: start,
            watchedIntervals: try watchedIntervals(since: start.epochMillis),
            now: now,
            targetHour: targetHour,
            calendar: calendar
        ) {
            try freezeDay(dayStart: start, dayEnd: end, calendar: calendar)
            start = end
            try database.run("UPDATE open_day SET day_start_ms = ? WHERE id = 1", [.int(start.epochMillis)])
        }
        return start
    }

    /// Record `[dayStart, dayEnd)`'s boundary into `rolled_day` — never
    /// re-evaluated once written, which is what keeps a frozen Day's label and
    /// boundaries stable regardless of what happens to its rollup afterward —
    /// then best-effort compute its `rollup_slice` rows immediately.
    ///
    /// The boundary write always succeeds; the rollup half may not (a
    /// provisional Segment still in `[dayStart, dayEnd)` — the open Day's own
    /// trailing View can still be mid-flight when the hard cap forces a Day
    /// closed). When it doesn't, the Day sits with `rollup_complete = 0` until
    /// `reconcile` retries it — this is the crash/blocked window ADR 0004's
    /// reconciliation pass exists for.
    private func freezeDay(dayStart: Date, dayEnd: Date, calendar: Calendar) throws {
        let label = DayBoundary.label(for: dayStart, calendar: calendar)
        try database.run(
            """
            INSERT INTO rolled_day (logical_date, day_start_ms, day_end_ms, schema_version, rollup_complete)
            VALUES (?, ?, ?, ?, 0)
            ON CONFLICT(logical_date) DO NOTHING
            """,
            [.text(label), .int(dayStart.epochMillis), .int(dayEnd.epochMillis), .int(schemaVersion)]
        )
        try tryComputeRollupSlices(label: label, startMs: dayStart.epochMillis, endMs: dayEnd.epochMillis)
    }

    /// Compute and store `label`'s `rollup_slice` rows and mark it complete —
    /// unless a provisional Segment still overlaps its window, in which case
    /// this is a silent no-op and the Day is retried later by `reconcile`.
    private func tryComputeRollupSlices(label: String, startMs: Int, endMs: Int) throws {
        guard try !hasProvisionalSegment(startMs: startMs, endMs: endMs) else { return }
        try recomputeSlices(label: label, startMs: startMs, endMs: endMs)
        try database.run("UPDATE rolled_day SET rollup_complete = 1 WHERE logical_date = ?", [.text(label)])
    }

    /// Delete and recompute `label`'s `rollup_slice` rows from `segments`.
    /// Only ever called for a Day whose rollup either never succeeded yet
    /// (`tryComputeRollupSlices`) or is being explicitly rebuilt (schema
    /// mismatch, or the manual "Rebuild statistics" action) — never for an
    /// already-complete Day outside of those, which is what keeps a frozen
    /// Day's numbers stable against a later out-of-order Flush.
    private func recomputeSlices(label: String, startMs: Int, endMs: Int) throws {
        let slices = try slicedTotals(startMs: startMs, endMs: endMs)
        try database.run("DELETE FROM rollup_slice WHERE logical_date = ?", [.text(label)])
        for slice in slices {
            try database.run(
                """
                INSERT INTO rollup_slice (logical_date, service, content_format, watched_ms, background_ms)
                VALUES (?, ?, ?, ?, ?)
                """,
                [.text(label), .text(slice.service), .text(slice.contentFormat), .int(slice.totals.watchedMs), .int(slice.totals.backgroundMs)]
            )
        }
    }

    /// Whether any Segment with `provisional = 1` overlaps `[startMs, endMs)`
    /// — the rollup job's guard against caching a Day whose trailing Segment
    /// is still subject to wholesale replacement (ADR 0004, `Segment.swift`).
    private func hasProvisionalSegment(startMs: Int, endMs: Int) throws -> Bool {
        var found = false
        try database.query(
            "SELECT 1 FROM segments WHERE provisional = 1 AND wall_end_ms > ? AND wall_start_ms < ? LIMIT 1",
            [.int(startMs), .int(endMs)]
        ) { _ in found = true }
        return found
    }

    /// Repair what the rollup job could not finish the first time: a
    /// `rolled_day` row whose `schema_version` no longer matches (rebuilt
    /// from its already-known, never-re-evaluated boundary — no need to
    /// re-derive it), and any Day still `rollup_complete = 0` whose
    /// provisional Segment has since resolved. Cheap and idempotent — safe to
    /// run on every read, which is what makes it double as the "on App
    /// launch" reconciliation pass ADR 0004 calls for.
    private func reconcile(calendar: Calendar) throws {
        var stale: [(label: String, startMs: Int, endMs: Int)] = []
        try database.query(
            "SELECT logical_date, day_start_ms, day_end_ms FROM rolled_day WHERE rollup_complete = 1 AND schema_version != ?",
            [.int(schemaVersion)]
        ) { row in stale.append((row.text(0), row.int(1), row.int(2))) }
        for day in stale {
            try recomputeSlices(label: day.label, startMs: day.startMs, endMs: day.endMs)
            try database.run(
                "UPDATE rolled_day SET schema_version = ? WHERE logical_date = ?",
                [.int(schemaVersion), .text(day.label)]
            )
        }

        var pending: [(label: String, startMs: Int, endMs: Int)] = []
        try database.query(
            "SELECT logical_date, day_start_ms, day_end_ms FROM rolled_day WHERE rollup_complete = 0"
        ) { row in pending.append((row.text(0), row.int(1), row.int(2))) }
        for day in pending {
            try tryComputeRollupSlices(label: day.label, startMs: day.startMs, endMs: day.endMs)
        }
    }

    /// Replay the Day-boundary walk over `segments` from its earliest known
    /// activity up to the current open Day, freezing and rolling up every Day
    /// it finds — used only by `rebuildStatistics`, where both rollup tables
    /// are empty and there is nothing yet to resume from.
    private func rebuildFromSegments(now: Date, calendar: Calendar) throws {
        guard let openStart = try openDayStartRaw() else { return }
        guard let earliest = try earliestSegmentStartMs() else { return }
        let targetHour = try targetHourRaw()

        var cursor = earliest
        while cursor < openStart.epochMillis {
            let cursorDate = Date(epochMillis: cursor)
            guard let end = DayBoundary.confirmedEnd(
                dayStart: cursorDate,
                watchedIntervals: try watchedIntervals(since: cursor),
                now: now,
                targetHour: targetHour,
                calendar: calendar
            ) else { break }
            try freezeDay(dayStart: cursorDate, dayEnd: end, calendar: calendar)
            cursor = end.epochMillis
        }
    }

    /// Resolve `kind` to an absolute `[startMs, endMs)` plus whether it runs
    /// through the still-live open Day.
    private func resolveRange(
        _ kind: DateRangeKind,
        openStart: Date,
        calendar: Calendar
    ) throws -> (startMs: Int, endMs: Int, includesOpenDay: Bool) {
        let openLabel = DayBoundary.label(for: openStart, calendar: calendar)

        switch kind {
        case .today:
            return (openStart.epochMillis, openStart.epochMillis, true)

        case .thisWeek:
            let monday = mostRecentMonday(onOrBefore: openStart, calendar: calendar)
            let start = try dayStart(forLabel: DayBoundary.label(for: monday, calendar: calendar), openStart: openStart, openLabel: openLabel)
            return (start, openStart.epochMillis, true)

        case .thisMonth:
            let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: openStart))!
            let start = try dayStart(forLabel: DayBoundary.label(for: firstOfMonth, calendar: calendar), openStart: openStart, openLabel: openLabel)
            return (start, openStart.epochMillis, true)

        case .custom(let from, let through):
            let fromLabel = DayBoundary.label(for: from, calendar: calendar)
            let throughLabel = DayBoundary.label(for: through, calendar: calendar)
            let start = try dayStart(forLabel: fromLabel, openStart: openStart, openLabel: openLabel)
            if throughLabel >= openLabel {
                // The open Day, or a date not reached yet: clip to it.
                return (start, openStart.epochMillis, true)
            }
            let end = try dayEnd(forLabel: throughLabel) ?? openStart.epochMillis
            return (start, end, false)
        }
    }

    /// The most recent Monday on or before `date`'s calendar date (Week =
    /// Monday–Sunday, ADR 0001), as a Date on that calendar date.
    private func mostRecentMonday(onOrBefore date: Date, calendar: Calendar) -> Date {
        let dayOfMonth = calendar.startOfDay(for: date)
        // Gregorian `.weekday`: Sunday = 1 ... Saturday = 7. Days since the
        // most recent Monday: Monday(2)→0, Sunday(1)→6.
        let weekday = calendar.component(.weekday, from: dayOfMonth)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: dayOfMonth) ?? dayOfMonth
    }

    /// A labelled Day's `day_start_ms` — the open Day's own start if the
    /// label matches it, else the `rolled_day` row (whose boundary is fixed
    /// the moment it's written, regardless of rollup completeness), else (the
    /// label predates any known Day) the earliest Day this store has ever seen.
    private func dayStart(forLabel label: String, openStart: Date, openLabel: String) throws -> Int {
        if label == openLabel { return openStart.epochMillis }
        if let frozen = try rolledDayBoundaryMs(column: "day_start_ms", forLabel: label) { return frozen }
        return try earliestKnownDayStartMs() ?? openStart.epochMillis
    }

    private func dayEnd(forLabel label: String) throws -> Int? {
        try rolledDayBoundaryMs(column: "day_end_ms", forLabel: label)
    }

    /// `column` is always one of `day_start_ms` / `day_end_ms` — both
    /// call sites are internal and pass a literal, never user input.
    private func rolledDayBoundaryMs(column: String, forLabel label: String) throws -> Int? {
        var result: Int?
        try database.query("SELECT \(column) FROM rolled_day WHERE logical_date = ?", [.text(label)]) { row in
            result = row.int(0)
        }
        return result
    }

    private func earliestKnownDayStartMs() throws -> Int? {
        var result: Int?
        try database.query("SELECT MIN(day_start_ms) FROM rolled_day") { row in
            result = row.optionalInt(0)
        }
        return result
    }

    private func earliestSegmentStartMs() throws -> Int? {
        var result: Int?
        try database.query("SELECT MIN(wall_start_ms) FROM segments") { row in
            result = row.optionalInt(0)
        }
        return result
    }

    /// The sum of every fully processed Day's `rollup_slice` rows fully
    /// contained in `[startMs, endMs)`, grouped by `service × contentFormat`
    /// — never the live `segments` table, so a frozen Day's contribution
    /// cannot change after the fact.
    private func frozenSlices(startMs: Int, endMs: Int) throws -> [TotalsSlice] {
        var slices: [TotalsSlice] = []
        try database.query(
            """
            SELECT rs.service, rs.content_format, SUM(rs.watched_ms), SUM(rs.background_ms)
            FROM rollup_slice rs
            JOIN rolled_day rd ON rd.logical_date = rs.logical_date
            WHERE rd.rollup_complete = 1 AND rd.day_start_ms >= ? AND rd.day_end_ms <= ?
            GROUP BY rs.service, rs.content_format
            """,
            [.int(startMs), .int(endMs)]
        ) { row in
            slices.append(TotalsSlice(
                service: row.text(0),
                contentFormat: row.text(1),
                totals: Totals(watchedMs: row.int(2), backgroundMs: row.int(3))
            ))
        }
        return slices
    }

    private func loadFrozenDays() throws -> [FrozenDay] {
        var days: [FrozenDay] = []
        try database.query(
            """
            SELECT rd.logical_date, rd.day_start_ms, rd.day_end_ms,
                   COALESCE(SUM(rs.watched_ms), 0), COALESCE(SUM(rs.background_ms), 0)
            FROM rolled_day rd
            LEFT JOIN rollup_slice rs ON rs.logical_date = rd.logical_date
            WHERE rd.rollup_complete = 1
            GROUP BY rd.logical_date
            ORDER BY rd.day_start_ms
            """
        ) { row in
            days.append(FrozenDay(
                label: row.text(0),
                dayStartMs: row.int(1),
                dayEndMs: row.int(2),
                watchedMs: row.int(3),
                backgroundMs: row.int(4)
            ))
        }
        return days
    }

    /// The merged watched-time timeline the boundary detector needs: only
    /// `watched` Segments (ADR 0001 — background audio never holds a Day
    /// open) ending after `startMs`, across every View.
    private func watchedIntervals(since startMs: Int) throws -> [DateInterval] {
        var intervals: [DateInterval] = []
        try database.query(
            "SELECT wall_start_ms, wall_end_ms FROM segments WHERE kind = 'watched' AND wall_end_ms > ? ORDER BY wall_start_ms",
            [.int(startMs)]
        ) { row in
            intervals.append(DateInterval(start: Date(epochMillis: row.int(0)), end: Date(epochMillis: row.int(1))))
        }
        return intervals
    }

    private func openDayStartRaw() throws -> Date? {
        var result: Int?
        try database.query("SELECT day_start_ms FROM open_day WHERE id = 1") { row in
            result = row.int(0)
        }
        return result.map(Date.init(epochMillis:))
    }

    private func targetHourRaw() throws -> Int {
        var hour = DayBoundary.defaultTargetHour
        try database.query("SELECT target_hour FROM day_settings WHERE id = 1") { row in
            hour = row.int(0)
        }
        return hour
    }

    /// `totals(in:)` without the lock, for internal callers that already hold it.
    private func rawTotals(range: DateRange) throws -> Totals {
        var totals = Totals()
        try database.query(
            """
            SELECT kind, SUM(MIN(wall_end_ms, ?) - MAX(wall_start_ms, ?))
            FROM segments
            WHERE wall_end_ms > ? AND wall_start_ms < ?
            GROUP BY kind
            """,
            [.int(range.endMs), .int(range.startMs), .int(range.startMs), .int(range.endMs)]
        ) { row in
            let milliseconds = row.optionalInt(1) ?? 0
            switch Segment.Kind(rawValue: row.text(0)) {
            case .watched: totals.watchedMs = milliseconds
            case .background: totals.backgroundMs = milliseconds
            case nil: break
            }
        }
        return totals
    }

    /// `slicedTotals` without the lock: `segments` joined to `views` and
    /// clipped to `[startMs, endMs)`, grouped by `service × contentFormat`
    /// (ADR 0004) — the live counterpart to `frozenSlices`, and what a fresh
    /// rollup computation sums from.
    private func slicedTotals(startMs: Int, endMs: Int) throws -> [TotalsSlice] {
        var byKey: [String: TotalsSlice] = [:]
        try database.query(
            """
            SELECT v.service, v.content_format, s.kind, SUM(MIN(s.wall_end_ms, ?) - MAX(s.wall_start_ms, ?))
            FROM segments s
            JOIN views v ON v.view_id = s.view_id
            WHERE s.wall_end_ms > ? AND s.wall_start_ms < ?
            GROUP BY v.service, v.content_format, s.kind
            """,
            [.int(endMs), .int(startMs), .int(startMs), .int(endMs)]
        ) { row in
            let service = row.text(0)
            let contentFormat = row.text(1)
            let key = "\(service)\u{0}\(contentFormat)"
            var slice = byKey[key] ?? TotalsSlice(service: service, contentFormat: contentFormat, totals: Totals())
            let milliseconds = row.optionalInt(3) ?? 0
            switch Segment.Kind(rawValue: row.text(2)) {
            case .watched: slice.totals.watchedMs = milliseconds
            case .background: slice.totals.backgroundMs = milliseconds
            case nil: break
            }
            byKey[key] = slice
        }
        return Array(byKey.values)
    }

    /// A View's Segments, oldest first. The History pane's raw material; for now
    /// it is how the shape of a computed View is inspected.
    public func segments(viewId: String) throws -> [Segment] {
        lock.lock()
        defer { lock.unlock() }
        return try loadSegments(viewId: viewId)
    }

    /// Row counts, for tests that need to see that a rejected Flush stored
    /// nothing.
    public struct Counts: Equatable, Sendable {
        public var flushes = 0
        public var views = 0
        public var rawEvents = 0
        public var segments = 0
    }

    public func counts() throws -> Counts {
        lock.lock()
        defer { lock.unlock() }

        var counts = Counts()
        for (table, keyPath) in [
            ("flushes", \Counts.flushes),
            ("views", \Counts.views),
            ("raw_events", \Counts.rawEvents),
            ("segments", \Counts.segments),
        ] as [(String, WritableKeyPath<Counts, Int>)] {
            try database.query("SELECT COUNT(*) FROM \(table)") { row in
                counts[keyPath: keyPath] = row.int(0)
            }
        }
        return counts
    }

    // MARK: - Writing the log

    private func upsert(_ view: FlushView) throws {
        try database.run(
            """
            INSERT INTO views (
                view_id, service, content_format, embedded, video_id, url, title, author,
                duration_sec, metadata_source, adapter_id, tab_id, started_at_ms, open, previous_view_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(view_id) DO UPDATE SET
                service = excluded.service,
                content_format = excluded.content_format,
                embedded = excluded.embedded,
                video_id = excluded.video_id,
                url = excluded.url,
                title = excluded.title,
                author = excluded.author,
                duration_sec = excluded.duration_sec,
                metadata_source = excluded.metadata_source,
                adapter_id = excluded.adapter_id,
                tab_id = excluded.tab_id,
                started_at_ms = excluded.started_at_ms,
                open = excluded.open,
                previous_view_id = excluded.previous_view_id
            """,
            [
                .text(view.viewId),
                .text(view.service),
                .text(view.contentFormat),
                .bool(view.embedded),
                .text(view.videoId),
                .text(view.url),
                .optionalText(view.title),
                .optionalText(view.author),
                .optionalDouble(view.durationSec),
                .optionalText(view.metadataSource),
                .optionalText(view.adapterId),
                .int(view.tabId),
                .int(view.startedAt),
                .bool(view.open),
                .optionalText(view.previousViewId),
            ]
        )
    }

    /// Append-only, with no uniqueness constraint on `(view_id, seq)`: the same
    /// Event may legitimately land twice (ADR 0002) and consumers de-duplicate.
    private func append(_ event: RawEvent, to viewId: String) throws {
        try database.run(
            """
            INSERT INTO raw_events (view_id, seq, type, t_ms, pos, seek_from, seek_to, rate, playing, visible, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(viewId),
                .int(event.seq),
                .text(event.type.name),
                .int(event.t),
                .optionalDouble(event.pos),
                .optionalDouble(event.from),
                .optionalDouble(event.to),
                .optionalDouble(event.rate),
                .optionalBool(event.playing),
                .optionalBool(event.visible),
                .optionalText(event.reason),
            ]
        )
    }

    // MARK: - Deriving Segments

    /// Re-derive a View's Segments from its whole log and swap them in.
    ///
    /// A full replace, never an append: Segment computation is a pure function of
    /// the ordered log, so re-running it after a late or duplicated batch is how
    /// the App stays idempotent — and it is what replaces an open View's
    /// `provisional` tail.
    private func recomputeSegments(viewId: String) throws {
        let segments = SegmentComputer.segments(viewId: viewId, events: try loadEvents(viewId: viewId))
        try database.run("DELETE FROM segments WHERE view_id = ?", [.text(viewId)])
        for segment in segments {
            try database.run(
                """
                INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(segment.viewId),
                    .text(segment.kind.rawValue),
                    .int(segment.wallStartMs),
                    .int(segment.wallEndMs),
                    .optionalDouble(segment.posStart),
                    .optionalDouble(segment.posEnd),
                    .bool(segment.provisional),
                ]
            )
        }
    }

    private func loadEvents(viewId: String) throws -> [RawEvent] {
        var events: [RawEvent] = []
        try database.query(
            """
            SELECT seq, type, t_ms, pos, seek_from, seek_to, rate, playing, visible, reason
            FROM raw_events WHERE view_id = ? ORDER BY seq, id
            """,
            [.text(viewId)]
        ) { row in
            events.append(RawEvent(
                seq: row.int(0),
                type: EventType(name: row.text(1)),
                t: row.int(2),
                pos: row.optionalDouble(3),
                from: row.optionalDouble(4),
                to: row.optionalDouble(5),
                rate: row.optionalDouble(6),
                playing: row.optionalInt(7).map { $0 != 0 },
                visible: row.optionalInt(8).map { $0 != 0 },
                reason: row.optionalText(9)
            ))
        }
        return events
    }

    private func loadSegments(viewId: String) throws -> [Segment] {
        var segments: [Segment] = []
        try database.query(
            """
            SELECT kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional
            FROM segments WHERE view_id = ? ORDER BY wall_start_ms, id
            """,
            [.text(viewId)]
        ) { row in
            segments.append(Segment(
                viewId: viewId,
                kind: Segment.Kind(rawValue: row.text(0)) ?? .watched,
                wallStartMs: row.int(1),
                wallEndMs: row.int(2),
                posStart: row.optionalDouble(3),
                posEnd: row.optionalDouble(4),
                provisional: row.bool(5)
            ))
        }
        return segments
    }

    private func highestSeq(viewId: String) throws -> Int {
        var highest = 0
        try database.query(
            "SELECT MAX(seq) FROM raw_events WHERE view_id = ?",
            [.text(viewId)]
        ) { row in
            highest = row.optionalInt(0) ?? 0
        }
        return highest
    }

    private func storedAck(flushId: String) throws -> Ack? {
        var json: String?
        try database.query("SELECT ack_json FROM flushes WHERE flush_id = ?", [.text(flushId)]) { row in
            json = row.text(0)
        }
        guard let json else { return nil }
        return try? JSONDecoder().decode(Ack.self, from: Data(json.utf8))
    }

    // MARK: - Schema

    private static let schema = """
        CREATE TABLE IF NOT EXISTS flushes (
            flush_id       TEXT PRIMARY KEY,
            received_at_ms INTEGER NOT NULL,
            ack_json       TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS views (
            view_id          TEXT PRIMARY KEY,
            service          TEXT NOT NULL,
            content_format   TEXT NOT NULL,
            embedded         INTEGER NOT NULL,
            video_id         TEXT NOT NULL,
            url              TEXT NOT NULL,
            title            TEXT,
            author           TEXT,
            duration_sec     REAL,
            metadata_source  TEXT,
            adapter_id       TEXT,
            tab_id           INTEGER NOT NULL,
            started_at_ms    INTEGER NOT NULL,
            open             INTEGER NOT NULL,
            previous_view_id TEXT
        );

        CREATE TABLE IF NOT EXISTS raw_events (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            view_id   TEXT NOT NULL,
            seq       INTEGER NOT NULL,
            type      TEXT NOT NULL,
            t_ms      INTEGER NOT NULL,
            pos       REAL,
            seek_from REAL,
            seek_to   REAL,
            rate      REAL,
            playing   INTEGER,
            visible   INTEGER,
            reason    TEXT
        );
        CREATE INDEX IF NOT EXISTS raw_events_by_view ON raw_events (view_id, seq);

        CREATE TABLE IF NOT EXISTS segments (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            view_id       TEXT NOT NULL,
            kind          TEXT NOT NULL,
            wall_start_ms INTEGER NOT NULL,
            wall_end_ms   INTEGER NOT NULL,
            pos_start     REAL,
            pos_end       REAL,
            provisional   INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS segments_by_view ON segments (view_id);
        CREATE INDEX IF NOT EXISTS segments_by_wall_clock ON segments (wall_start_ms, wall_end_ms);

        CREATE TABLE IF NOT EXISTS rolled_day (
            logical_date    TEXT PRIMARY KEY,
            day_start_ms    INTEGER NOT NULL,
            day_end_ms      INTEGER NOT NULL,
            schema_version  INTEGER NOT NULL,
            rollup_complete INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS rolled_day_by_start ON rolled_day (day_start_ms);

        CREATE TABLE IF NOT EXISTS rollup_slice (
            logical_date   TEXT NOT NULL,
            service        TEXT NOT NULL,
            content_format TEXT NOT NULL,
            watched_ms     INTEGER NOT NULL,
            background_ms  INTEGER NOT NULL,
            PRIMARY KEY (logical_date, service, content_format)
        );
        CREATE INDEX IF NOT EXISTS rollup_slice_by_date ON rollup_slice (logical_date);

        CREATE TABLE IF NOT EXISTS open_day (
            id           INTEGER PRIMARY KEY CHECK (id = 1),
            day_start_ms INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS day_settings (
            id          INTEGER PRIMARY KEY CHECK (id = 1),
            target_hour INTEGER NOT NULL
        );
        """
}
