import Foundation

/// How a `segments.kind`/summed-milliseconds row read from SQL lands on a
/// `Totals` — shared by every query that groups Segments by `kind`.
extension Totals {
    fileprivate mutating func set(_ kind: Segment.Kind?, milliseconds: Int) {
        switch kind {
        case .watched: watchedMs = milliseconds
        case .background: backgroundMs = milliseconds
        case nil: break
        }
    }
}

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
        // Older stores created before the private-window setting need this
        // additive migration. Fresh stores already get the column from schema.
        try? database.execute("ALTER TABLE app_settings ADD COLUMN capture_private_windows INTEGER NOT NULL DEFAULT 0")
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
            // An open View must retain its complete Event log: the next Flush
            // recomputes its Segments from that log. Closed Views are immutable,
            // so their raw facts can age out without changing derived history.
            _ = try pruneRawEventsRaw(now: Date(epochMillis: serverTime))
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
    ///
    /// v2: `slicedTotals` splits a YouTube Short (`/shorts/` path) into its own
    /// `content_format = "short"` slice instead of folding it into "standard".
    public static let currentSchemaVersion = 2

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

    /// One rollup-backed stack for every Day in the resolved range. Empty Days
    /// remain explicit entries rather than disappearing with their absent
    /// `rollup_slice` rows, which is what makes Trends truthful.
    public func dailySeries(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> [DaySeriesEntry] {
        lock.lock()
        defer { lock.unlock() }
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        try reconcile(calendar: calendar)
        let openLabel = DayBoundary.label(for: openStart, calendar: calendar)
        return try resolvedDayLabels(for: kind, openLabel: openLabel, calendar: calendar).map { label in
            let slices: [TotalsSlice]
            if label == openLabel {
                slices = try slicedTotals(startMs: openStart.epochMillis, endMs: now.epochMillis)
            } else {
                slices = try frozenSlices(forLabel: label)
            }
            return DaySeriesEntry(label: label, totals: Self.displayTotals(from: slices))
        }
    }

    /// The data at the rollup grain after unadapted Services are folded into
    /// the user-facing Other sites bucket.
    public func displayServiceTotals(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> [ServiceDisplayBucketTotal] {
        lock.lock()
        defer { lock.unlock() }
        let slices = try rawSlices(for: kind, now: now, calendar: calendar)
        var totals: [ServiceDisplayBucket: ServiceDisplayBucketTotal] = [:]
        for slice in slices {
            let display = ServiceDisplayBucket.from(service: slice.service)
            var entry = totals[display] ?? ServiceDisplayBucketTotal(service: display, totals: Totals(), formats: [])
            entry.totals.watchedMs += slice.totals.watchedMs
            entry.totals.backgroundMs += slice.totals.backgroundMs
            entry.formats.append(slice)
            totals[display] = entry
        }
        let embeddedWatchedMs = try embeddedYouTubeWatchedMsRaw(for: kind, now: now, calendar: calendar)
        if var youtube = totals[.youtube] {
            youtube.embeddedWatchedMs = embeddedWatchedMs
            totals[.youtube] = youtube
        }
        return totals.values.sorted { $0.totals.watchedMs > $1.totals.watchedMs }
    }

    /// Watched time from embedded YouTube Views in the resolved range. Format
    /// rows still come from `rollup_slice`; `embedded` belongs to `views`, so
    /// this one display detail reads the derived Segments directly.
    public func embeddedYouTubeWatchedMs(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return try embeddedYouTubeWatchedMsRaw(for: kind, now: now, calendar: calendar)
    }

    /// The videos watched under each activity-flexed Day in the resolved range,
    /// one row per video (not per View — every View of the same video that Day
    /// is folded into one row). Frozen Days use their captured boundaries; the
    /// current open Day is clipped at `now`. Coverage unions watched
    /// media-position intervals across every folded View, so replaying the same
    /// passage cannot exceed the known video duration.
    public func history(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> [HistoryDay] {
        lock.lock()
        defer { lock.unlock() }
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        try reconcile(calendar: calendar)
        let openLabel = DayBoundary.label(for: openStart, calendar: calendar)
        let days = try resolvedDayLabels(for: kind, openLabel: openLabel, calendar: calendar).compactMap { label -> HistoryDay? in
            let bounds: (Int, Int)
            if label == openLabel {
                bounds = (openStart.epochMillis, now.epochMillis)
            } else if let start = try rolledDayBoundaryMs(column: "day_start_ms", forLabel: label),
                      let end = try rolledDayBoundaryMs(column: "day_end_ms", forLabel: label) {
                bounds = (start, end)
            } else {
                return nil
            }
            let videos = try historyVideos(startMs: bounds.0, endMs: bounds.1, isOpenDay: label == openLabel)
            guard !videos.isEmpty else { return nil }
            return HistoryDay(
                label: label,
                watchedMs: videos.reduce(0) { $0 + $1.watchedMs },
                isOpen: label == openLabel,
                firstAt: videos.map(\.firstWatchedAt).min() ?? Date(epochMillis: bounds.0),
                lastAt: videos.map(\.lastWatchedAt).max() ?? Date(epochMillis: bounds.1),
                videos: videos
            )
        }
        // Newest Day first — the open Day (or the most recent one with activity)
        // sits at the top of the pane, matching the newest-first video order
        // inside each Day. `resolvedDayLabels` stays oldest-first for Trends.
        return Array(days.reversed())
    }

    /// The current open activity-flexed Day, for calendar highlighting.
    public func activityDay(now: Date, calendar: Calendar = .current) throws -> Date {
        lock.lock()
        defer { lock.unlock() }
        return try advanceOpenDay(now: now, calendar: calendar)
    }

    /// The current open Day's activity-flexed label, for display.
    public func activityDayLabel(now: Date, calendar: Calendar = .current) throws -> String {
        let day = try activityDay(now: now, calendar: calendar)
        return DayBoundary.label(for: day, calendar: calendar)
    }

    /// A human-readable inclusive label for the calendar/title row.
    public func rangeLabel(for kind: DateRangeKind, now: Date, calendar: Calendar = .current) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        let openLabel = DayBoundary.label(for: openStart, calendar: calendar)
        let labels = try resolvedDayLabels(for: kind, openLabel: openLabel, calendar: calendar)
        guard let first = labels.first, let last = labels.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let firstDate = try date(forLabel: first, calendar: calendar)
        let lastDate = try date(forLabel: last, calendar: calendar)
        return first == last ? formatter.string(from: firstDate) : "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
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

    /// When the most recent Flush landed, or `nil` if none ever has — "an
    /// Extension is paired" for the UI (issue #35 §3's refresh button), read
    /// straight off `flushes` rather than a separate in-memory flag.
    public func lastFlushAt() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
        var ms = 0
        try database.query("SELECT COALESCE(MAX(received_at_ms), 0) FROM flushes") { row in ms = row.int(0) }
        return ms > 0 ? Date(epochMillis: ms) : nil
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

    /// Number of days raw Events are retained. The default is 90. Zero deletes
    /// raw Events from closed Views on the next accepted Flush or settings save;
    /// open Views keep their full log until they close so recomputation is safe.
    /// Views, Segments, and both rollup tables are kept forever.
    public func rawEventRetentionDays() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try rawEventRetentionDaysRaw()
    }

    public func setRawEventRetentionDays(_ days: Int) throws {
        lock.lock(); defer { lock.unlock() }
        try database.run("INSERT INTO app_settings (id, raw_event_retention_days) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET raw_event_retention_days = excluded.raw_event_retention_days", [.int(max(0, days))])
    }

    /// Whether the paired Extension may capture playback in private windows.
    /// It defaults off and is read through the authenticated loopback contract.
    public func capturesPrivateWindows() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var enabled = false
        try database.query("SELECT capture_private_windows FROM app_settings WHERE id = 1") { row in enabled = row.bool(0) }
        return enabled
    }

    public func setCapturesPrivateWindows(_ enabled: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        try database.run("INSERT INTO app_settings (id, capture_private_windows) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET capture_private_windows = excluded.capture_private_windows", [.bool(enabled)])
    }

    /// Delete raw Event facts older than the configured retention window. This
    /// runs when Settings changes the window and never deletes derived or
    /// historical tables (`segments`, `rolled_day`, `rollup_slice`).
    @discardableResult
    public func pruneRawEvents(now: Date) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try pruneRawEventsRaw(now: now)
    }

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

    private func embeddedYouTubeWatchedMsRaw(for kind: DateRangeKind, now: Date, calendar: Calendar) throws -> Int {
        let openStart = try advanceOpenDay(now: now, calendar: calendar)
        try reconcile(calendar: calendar)
        let resolved = try resolveRange(kind, openStart: openStart, calendar: calendar)
        let endMs = resolved.includesOpenDay ? now.epochMillis : resolved.endMs
        var watchedMs = 0
        try database.query(
            """
            SELECT COALESCE(SUM(MIN(s.wall_end_ms, ?) - MAX(s.wall_start_ms, ?)), 0)
            FROM segments s JOIN views v ON v.view_id = s.view_id
            WHERE s.kind = 'watched' AND v.service = 'youtube' AND v.embedded = 1
              AND s.wall_end_ms > ? AND s.wall_start_ms < ?
            """,
            [.int(endMs), .int(resolved.startMs), .int(resolved.startMs), .int(endMs)]
        ) { row in watchedMs = row.int(0) }
        return watchedMs
    }

    /// Sum `a` and `b`'s contributions to each `service × contentFormat` key
    /// into one entry per key — how a frozen-Days total and the live open Day
    /// combine into one slice list rather than two rows for the same key.
    private static func merge(_ a: [TotalsSlice], _ b: [TotalsSlice]) -> [TotalsSlice] {
        var byKey: [String: TotalsSlice] = [:]
        for slice in a + b {
            let key = sliceKey(service: slice.service, contentFormat: slice.contentFormat)
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

    /// The `service × contentFormat` grouping key `slicedTotals` and `merge`
    /// share — `\u{0}` cannot appear in either field, so it never collides.
    private static func sliceKey(service: String, contentFormat: String) -> String {
        "\(service)\u{0}\(contentFormat)"
    }

    /// A Flush this recent means ingest is still active.
    private static let ingestActiveWindowMs = 15_000
    /// While ingest is active, activity this far behind `now` means a buffered
    /// backlog (ADR 0002 at-least-once delivery) is still draining — one View
    /// per Flush, in no useful order. Deciding a Day boundary now would lock it
    /// against a partial view of that backlog (the bug: a Day pinned to the
    /// bare target hour because the straddling View flushed a beat late — a
    /// decision ADR 0001 forbids re-evaluating). A later call once the drain
    /// catches up, or ingest goes quiet, does the freeze with everything in.
    private static let ingestCaughtUpMs = 120_000

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

        if try backlogIsDraining(now: now) { return start }

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

    /// True when a Flush landed within `ingestActiveWindowMs` of `now` yet the
    /// newest activity on record is still more than `ingestCaughtUpMs` behind
    /// it — a buffered backlog is mid-drain and the boundary detector would be
    /// deciding against only part of it. Real-time playback fails the second
    /// test (its heartbeats keep activity within seconds of `now`); a genuine
    /// quiet spell fails the first (no Flushes arriving) — both still freeze.
    private func backlogIsDraining(now: Date) throws -> Bool {
        var lastFlushMs = 0
        try database.query("SELECT COALESCE(MAX(received_at_ms), 0) FROM flushes") { row in lastFlushMs = row.int(0) }
        guard lastFlushMs >= now.epochMillis - Self.ingestActiveWindowMs else { return false }

        var newestActivityMs = 0
        try database.query("SELECT COALESCE(MAX(wall_end_ms), 0) FROM segments") { row in newestActivityMs = row.int(0) }
        try database.query("SELECT COALESCE(MAX(t_ms), 0) FROM raw_events") { row in newestActivityMs = max(newestActivityMs, row.int(0)) }
        return newestActivityMs < now.epochMillis - Self.ingestCaughtUpMs
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
        // Also stamps the current schema_version: a Day frozen while stale
        // and only unblocked later would otherwise sit complete under its old
        // version, and every subsequent reconcile would redo it needlessly.
        try database.run(
            "UPDATE rolled_day SET rollup_complete = 1, schema_version = ? WHERE logical_date = ?",
            [.int(schemaVersion), .text(label)]
        )
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
            // A Day already marked complete should never still hold a
            // provisional Segment — but if a late-arriving Flush reopened
            // one, the rollup job's guard (ADR 0004) applies here too: leave
            // it under its old schema_version and retry next reconcile.
            guard try !hasProvisionalSegment(startMs: day.startMs, endMs: day.endMs) else { continue }
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
    private func frozenSlices(forLabel label: String) throws -> [TotalsSlice] {
        var slices: [TotalsSlice] = []
        try database.query(
            """
            SELECT service, content_format, watched_ms, background_ms
            FROM rollup_slice
            WHERE logical_date = ?
              AND EXISTS (SELECT 1 FROM rolled_day WHERE logical_date = ? AND rollup_complete = 1)
            """,
            [.text(label), .text(label)]
        ) { row in
            slices.append(TotalsSlice(
                service: row.text(0), contentFormat: row.text(1),
                totals: Totals(watchedMs: row.int(2), backgroundMs: row.int(3))
            ))
        }
        return slices
    }

    private static func displayTotals(from slices: [TotalsSlice]) -> [ServiceDisplayBucket: Totals] {
        slices.reduce(into: [:]) { totals, slice in
            let service = ServiceDisplayBucket.from(service: slice.service)
            var total = totals[service] ?? Totals()
            total.watchedMs += slice.totals.watchedMs
            total.backgroundMs += slice.totals.backgroundMs
            totals[service] = total
        }
    }

    private func resolvedDayLabels(for kind: DateRangeKind, openLabel: String, calendar: Calendar) throws -> [String] {
        let openDate = try date(forLabel: openLabel, calendar: calendar)
        let start: Date
        let end: Date
        switch kind {
        case .today:
            start = openDate
            end = openDate
        case .thisWeek:
            start = mostRecentMonday(onOrBefore: openDate, calendar: calendar)
            end = openDate
        case .thisMonth:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: openDate))!
            end = openDate
        case .custom(let from, let through):
            start = calendar.startOfDay(for: min(from, through))
            end = min(calendar.startOfDay(for: max(from, through)), openDate)
        }
        guard start <= end else { return [] }
        var labels: [String] = []
        var day = start
        while day <= end {
            labels.append(DayBoundary.label(for: day, calendar: calendar))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return labels
    }

    private func date(forLabel label: String, calendar: Calendar) throws -> Date {
        let pieces = label.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, let date = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])) else {
            throw SQLiteError.statement("invalid Day label", sql: label)
        }
        return date
    }

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

    private func rawEventRetentionDaysRaw() throws -> Int {
        var days = 90
        try database.query("SELECT raw_event_retention_days FROM app_settings WHERE id = 1") { row in days = row.int(0) }
        return days
    }

    private func pruneRawEventsRaw(now: Date) throws -> Int {
        let cutoff = now.epochMillis - (try rawEventRetentionDaysRaw()) * 86_400_000
        try database.run(
            """
            DELETE FROM raw_events
            WHERE t_ms < ?
              AND EXISTS (SELECT 1 FROM views WHERE views.view_id = raw_events.view_id AND views.open = 0)
            """,
            [.int(cutoff)]
        )
        var count = 0
        try database.query("SELECT changes()") { row in count = row.int(0) }
        return count
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
            totals.set(Segment.Kind(rawValue: row.text(0)), milliseconds: row.optionalInt(1) ?? 0)
        }
        return totals
    }

    /// `slicedTotals` without the lock: `segments` joined to `views` and
    /// clipped to `[startMs, endMs)`, grouped by `service × contentFormat`
    /// (ADR 0004) — the live counterpart to `frozenSlices`, and what a fresh
    /// rollup computation sums from.
    private func slicedTotals(startMs: Int, endMs: Int) throws -> [TotalsSlice] {
        var byKey: [String: TotalsSlice] = [:]
        // A YouTube Short is a "standard" View on a `/shorts/` path — the same
        // read-time recovery `readTimeContentFormat` does for the History pane,
        // pushed into SQL so it also lands in the `rollup_slice` rows this feeds
        // (bump `currentSchemaVersion` when this rule changes).
        try database.query(
            """
            SELECT service, content_format, kind, SUM(dur) FROM (
              SELECT v.service AS service,
                     CASE WHEN v.content_format = 'standard' AND instr(v.url, '/shorts/') > 0
                          THEN 'short' ELSE v.content_format END AS content_format,
                     s.kind AS kind,
                     MIN(s.wall_end_ms, ?) - MAX(s.wall_start_ms, ?) AS dur
              FROM segments s
              JOIN views v ON v.view_id = s.view_id
              WHERE s.wall_end_ms > ? AND s.wall_start_ms < ?
            )
            GROUP BY service, content_format, kind
            """,
            [.int(endMs), .int(startMs), .int(startMs), .int(endMs)]
        ) { row in
            let service = row.text(0)
            let contentFormat = row.text(1)
            let key = Self.sliceKey(service: service, contentFormat: contentFormat)
            var slice = byKey[key] ?? TotalsSlice(service: service, contentFormat: contentFormat, totals: Totals())
            slice.totals.set(Segment.Kind(rawValue: row.text(2)), milliseconds: row.optionalInt(3) ?? 0)
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
        var isLive = false
        try database.query("SELECT content_format FROM views WHERE view_id = ?", [.text(viewId)]) { row in
            isLive = row.text(0) == "live"
        }
        let segments = SegmentComputer.segments(viewId: viewId, events: try loadEvents(viewId: viewId), isLive: isLive)
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

    /// A video watched in the open Day counts as *playing now* when its newest
    /// watched Segment ends within this many milliseconds of `now` — one sample
    /// beat (`content.js` SAMPLE_MS = 5s) plus room for Flush latency.
    private static let playingGraceMs = 20_000

    /// How long after an orphan View's last watched moment its own tab may
    /// still name the video that time belongs to. The two gaps measured on a
    /// real database were 4.0 s and 5.1 s between a placeholder View's last
    /// watched Segment and the identified View that followed it, so this leaves
    /// comfortable room above them without reaching so far that an unrelated
    /// later click in the same tab could claim the time.
    private static let orphanAttributionWindowMs = 15_000

    /// Where each *orphan* View's watched time really belongs.
    ///
    /// A YouTube video starts playing seconds before YouTube's own router puts
    /// `?v=` in the address bar, so `content.js` opens the View under the
    /// generic page-address hash. `readTimeVideoId` rescues most of those from
    /// the View's own `url`, but a View that began on the bare home feed has no
    /// id anywhere in its own record to rescue — and every such View on that
    /// path shares one hash, so grouping them by id piles the opening seconds
    /// of unrelated videos into a single row wearing whichever title landed
    /// there last.
    ///
    /// The tab knows what the View does not: moments later that same tab opens
    /// the real video's View. So an orphan is attributed to the nearest later
    /// View in its own tab that names a real YouTube video. `previous_view_id`
    /// is deliberately not the mechanism here — the stored chain often points
    /// at a dead-end View that never accumulates watched time of its own, while
    /// the View actually carrying the watch is reachable only by tab and clock.
    ///
    /// An orphan with no such successor — a home-feed hover preview the user
    /// never clicked into — is reported as `unresolved` so the caller can drop
    /// it. Which video was previewed is unknowable after the fact, and letting
    /// it fold in with the next unrelated orphan sharing that hash is exactly
    /// the mislabelling this pass exists to end. Only which *video row* the
    /// time appears under changes: the Day's totals never key on video identity
    /// and are untouched.
    private func orphanAttribution(startMs: Int, endMs: Int) throws -> (real: [String: String], unresolved: Set<String>) {
        struct Candidate {
            var viewId: String
            var videoId: String
            var isYouTube: Bool
            var tabId: Int
            var startedAt: Int
            /// The end of this View's last watched Segment — `nil` when it
            /// never accumulated any, which is the dead-end shape above.
            var watchedEnd: Int?
            /// A generic page-address hash nothing could recover a video from.
            var isGeneric: Bool { videoId.hasPrefix("sha1:") }
        }

        var byTab: [Int: [Candidate]] = [:]
        var orphans: [Candidate] = []
        try database.query(
            """
            SELECT v.view_id, v.video_id, v.url, v.service, v.tab_id, v.started_at_ms,
                   (SELECT MAX(s.wall_end_ms) FROM segments s
                     WHERE s.view_id = v.view_id AND s.kind = 'watched')
            FROM views v
            WHERE (v.started_at_ms >= ? AND v.started_at_ms < ?)
               OR EXISTS (SELECT 1 FROM segments s WHERE s.view_id = v.view_id
                          AND s.wall_end_ms > ? AND s.wall_start_ms < ?)
            ORDER BY v.started_at_ms
            """,
            // Successors are looked for past the Day's own end: a video clicked
            // in the Day's last seconds is only named after it.
            [.int(startMs), .int(endMs + Self.orphanAttributionWindowMs), .int(startMs), .int(endMs)]
        ) { row in
            let candidate = Candidate(
                viewId: row.text(0),
                videoId: Self.readTimeVideoId(stored: row.text(1), url: row.text(2)),
                isYouTube: ServiceDisplayBucket.from(service: row.text(3)) == .youtube,
                tabId: row.int(4),
                startedAt: row.int(5),
                watchedEnd: row.optionalInt(6)
            )
            byTab[candidate.tabId, default: []].append(candidate)
            // Only YouTube routes a video's id through its address bar, so only
            // there does a generic id mean "identity lost". Everywhere else it
            // is the honest, intended identity of an Adapter-less page.
            if candidate.isYouTube, candidate.isGeneric {
                orphans.append(candidate)
            }
        }
        guard !orphans.isEmpty else { return ([:], []) }

        var real: [String: String] = [:]
        var unresolved: Set<String> = []
        for orphan in orphans {
            // A View that never played has no watched time to place.
            guard let watchedEnd = orphan.watchedEnd else { continue }
            // Rows arrive oldest-first, so the first match is the nearest one.
            // A successor may overlap the orphan's own tail — both keep sampling
            // for a beat — hence "started after the orphan started", measured
            // for lateness against the orphan's last watched moment.
            let successor = byTab[orphan.tabId]?.first { candidate in
                candidate.isYouTube && !candidate.isGeneric
                    && candidate.startedAt > orphan.startedAt
                    && candidate.startedAt <= watchedEnd + Self.orphanAttributionWindowMs
            }
            if let successor {
                real[orphan.viewId] = successor.videoId
            } else {
                unresolved.insert(orphan.viewId)
            }
        }
        return (real, unresolved)
    }

    private func historyVideos(startMs: Int, endMs: Int, isOpenDay: Bool) throws -> [HistoryVideo] {
        // Keyed by `display bucket \0 video id`: two Views of the same video —
        // a re-watch, a scroll back to an earlier Short, a re-mounted player —
        // fold into one row here. `\0` cannot appear in either field.
        struct Group {
            var videoId: String
            var service: String
            var contentFormat: String
            var embedded: Bool
            var title: String?
            var author: String?
            var url: String
            var latestStartedAt: Int
            var durationSec: Double?
            var open: Bool = false
            var watchedMs: Int = 0
            var minWallStart: Int = .max
            var maxWallEnd: Int = 0
            var viewIds: Set<String> = []
            var intervals: [(Double, Double)] = []
        }
        var groups: [String: Group] = [:]
        let attribution = try orphanAttribution(startMs: startMs, endMs: endMs)
        try database.query(
            """
            SELECT v.view_id, v.service, v.content_format, v.embedded, v.title, v.author,
                   v.started_at_ms, v.duration_sec, v.open, s.kind, s.wall_start_ms,
                   s.wall_end_ms, s.pos_start, s.pos_end, v.url, v.video_id
            FROM views v JOIN segments s ON s.view_id = v.view_id
            WHERE s.wall_end_ms > ? AND s.wall_start_ms < ?
            ORDER BY v.started_at_ms, s.wall_start_ms
            """,
            [.int(startMs), .int(endMs)]
        ) { row in
            let viewId = row.text(0)
            // An orphan nothing could place is left out of History entirely
            // rather than shown as a video it is not.
            guard !attribution.unresolved.contains(viewId) else { return }
            let service = row.text(1)
            let videoId = attribution.real[viewId] ?? Self.readTimeVideoId(stored: row.text(15), url: row.text(14))
            let startedAt = row.int(6)
            let key = "\(ServiceDisplayBucket.from(service: service))\u{0}\(videoId)"
            var group = groups[key] ?? Group(
                videoId: videoId, service: service, contentFormat: row.text(2), embedded: row.bool(3),
                title: row.optionalText(4), author: row.optionalText(5), url: row.text(14),
                latestStartedAt: startedAt, durationSec: row.optionalDouble(7)
            )
            group.viewIds.insert(viewId)
            group.open = group.open || row.bool(8)
            if let duration = row.optionalDouble(7) {
                group.durationSec = max(group.durationSec ?? 0, duration)
            }
            // Rows arrive in non-decreasing `started_at_ms` order, so the last
            // View seen for a video is its most recent — its metadata wins.
            if startedAt >= group.latestStartedAt {
                group.latestStartedAt = startedAt
                group.service = service
                group.contentFormat = row.text(2)
                group.embedded = row.bool(3)
                group.title = row.optionalText(4)
                group.author = row.optionalText(5)
                group.url = row.text(14)
            }
            guard Segment.Kind(rawValue: row.text(9)) == .watched else {
                groups[key] = group
                return
            }
            let wallStart = row.int(10)
            let wallEnd = row.int(11)
            let clippedStart = max(wallStart, startMs)
            let clippedEnd = min(wallEnd, endMs)
            group.watchedMs += clippedEnd - clippedStart
            group.minWallStart = min(group.minWallStart, clippedStart)
            group.maxWallEnd = max(group.maxWallEnd, clippedEnd)
            if let start = row.optionalDouble(12), let end = row.optionalDouble(13), wallEnd > wallStart {
                // Segments are whole in storage. When a Day cuts one, map each
                // clipped wall-clock edge onto that Segment's media timeline.
                let duration = Double(wallEnd - wallStart)
                let mediaStart = start + (end - start) * Double(clippedStart - wallStart) / duration
                let mediaEnd = start + (end - start) * Double(clippedEnd - wallStart) / duration
                group.intervals.append((min(mediaStart, mediaEnd), max(mediaStart, mediaEnd)))
            }
            groups[key] = group
        }
        return groups.map { key, group -> HistoryVideo in
            let coverage: Double?
            if group.contentFormat == "live" || group.durationSec == nil || group.durationSec! <= 0 {
                coverage = nil
            } else {
                let duration = group.durationSec!
                let sorted = group.intervals.map { (max(0, $0.0), min(duration, $0.1)) }
                    .filter { $0.0 < $0.1 }
                    .sorted { $0.0 < $1.0 }
                var covered = 0.0
                var current: (Double, Double)?
                for interval in sorted {
                    if let existing = current {
                        if interval.0 <= existing.1 {
                            current = (existing.0, max(existing.1, interval.1))
                        } else {
                            covered += existing.1 - existing.0
                            current = interval
                        }
                    } else {
                        current = interval
                    }
                }
                if let current { covered += current.1 - current.0 }
                coverage = min(1, covered / duration)
            }
            let isPlaying = isOpenDay && group.open && group.maxWallEnd >= endMs - Self.playingGraceMs
            return HistoryVideo(
                id: key, videoId: group.videoId,
                service: ServiceDisplayBucket.from(service: group.service), sourceService: group.service,
                contentFormat: Self.readTimeContentFormat(stored: group.contentFormat, url: group.url),
                embedded: group.embedded, title: group.title, author: group.author,
                firstWatchedAt: Date(epochMillis: group.minWallStart),
                lastWatchedAt: Date(epochMillis: group.maxWallEnd), watchedMs: group.watchedMs,
                watchCount: group.viewIds.count, knownDurationSec: group.durationSec,
                isOpen: group.open, isPlaying: isPlaying, coverage: coverage
            )
        }
        .filter { $0.watchedMs > 0 }
        // The video playing right now sorts to the very top; everything else by
        // when it was last watched, newest first.
        .sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.lastWatchedAt > rhs.lastWatchedAt
        }
    }

    /// A YouTube Short is a View whose page path is `/shorts/<id>`. The current
    /// Adapter-less extension slice reports every non-live View as "standard", so
    /// the "short" format is recovered from the URL at read time — the same
    /// read-time mapping `ServiceDisplayBucket.from` uses for the service. A
    /// stored "live" already carries its own format and is left untouched.
    static func readTimeContentFormat(stored: String, url: String) -> String {
        stored == "standard" && url.contains("/shorts/") ? "short" : stored
    }

    /// A generic-fallback View is identified by hashing the page's own address
    /// (`content.js`'s `videoIdFor`) rather than the video — deliberately, since
    /// most Adapter-less sites keep no id in their query string worth trusting.
    /// YouTube is the one site that does (`?v=`), so a stored id that is one of
    /// these hashes, on a View whose own `url` names a real YouTube video,
    /// recovers that video's true id here, at read time — the same technique
    /// `readTimeContentFormat` already uses for the Shorts format. Recovering to
    /// the exact id a bound Adapter would itself have reported (not some
    /// separately-namespaced value) means a View that briefly fell back to the
    /// hash before its Adapter caught up folds into the very same row as the
    /// rest of that watch, past or future, instead of sitting apart from it
    /// forever. A hover-preview whose own page never named a video (the bare
    /// home feed) has nothing to recover and keeps its shared, honestly
    /// anonymous id — there is no way to know, after the fact, which preview it
    /// was.
    static func readTimeVideoId(stored: String, url: String) -> String {
        guard stored.hasPrefix("sha1:"), let recovered = youTubeVideoId(fromURL: url) else { return stored }
        return recovered
    }

    /// The id a bound `YouTubeAdapter` would report for `url`, mirroring its own
    /// `fromUrl` (`extension/src/adapters/youtube.js`) — a watch page's `?v=`,
    /// or the id off `/shorts/`, `/live/`, `/embed/`. `nil` for anything else,
    /// including a URL with no video named at all.
    private static func youTubeVideoId(fromURL url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return nil }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let path = components.path
        if path == "/watch" {
            let id = components.queryItems?.first { $0.name == "v" }?.value
            return id?.isEmpty == false ? id : nil
        }
        for prefix in ["/shorts/", "/live/", "/embed/"] where path.hasPrefix(prefix) {
            let id = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
            return id?.isEmpty == false ? id : nil
        }
        return nil
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

        CREATE TABLE IF NOT EXISTS app_settings (
            id                       INTEGER PRIMARY KEY CHECK (id = 1),
            raw_event_retention_days INTEGER NOT NULL DEFAULT 90,
            capture_private_windows  INTEGER NOT NULL DEFAULT 0
        );
        """
}
