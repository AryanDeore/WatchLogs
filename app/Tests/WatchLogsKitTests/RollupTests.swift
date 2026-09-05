import Foundation
import Testing
@testable import WatchLogsKit

/// The daily rollup cache and the full read model (ADR 0004, issue #22):
/// `rolled_day` + `rollup_slice` behind `EventStore.slices(for:)` /
/// `totals(for:)`, the provisional-Segment guard, reconciliation, the
/// schema-version rebuild trigger, and the derived "needs an Adapter" flag.
/// Complements `DayRangeTests`, which exercises the Day-boundary seam this
/// slice's rollup job sits behind.
@Suite("Daily rollup cache and the full read model", .serialized)
struct RollupTests {
    private func post(_ body: Data, to service: LoopbackTransport, using client: RawHTTPClient) throws {
        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(service.pairing().token)", "Content-Type": "application/json"],
            body: body
        )
        #expect(response.status == 200)
    }

    /// 2024-01-01 is a fixed, unambiguous Monday.
    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func envelope(flushId: String = UUID().uuidString, views: [String]) -> Data {
        Data(#"""
        {"schemaVersion":1,"flushId":"\#(flushId)","sentAt":1700000000000,
         "agent":{"extInstanceId":"ext-1","extVersion":"0.1.0","browser":"chrome","os":"macOS"},
         "views":[\#(views.joined(separator: ","))]}
        """#.utf8)
    }

    /// One View, watched continuously from `startMs` for `durationMs` — just
    /// `play` then `viewEnded`, no gaps.
    private func session(
        viewId: String,
        startMs: Int,
        durationMs: Int,
        service: String = "youtube",
        contentFormat: String = "standard",
        adapterId: String? = "youtube"
    ) -> String {
        let adapterField = adapterId.map { #""\#($0)""# } ?? "null"
        return #"""
        {"viewId":"\#(viewId)","service":"\#(service)","contentFormat":"\#(contentFormat)","embedded":false,
         "videoId":"v","url":"https://example.com/v","tabId":1,"startedAt":\#(startMs),
         "adapterId":\#(adapterField),
         "open":false,"previousViewId":null,"events":[
           { "seq": 1, "type": "mediaFound", "t": \#(startMs), "pos": 0 },
           { "seq": 2, "type": "play", "t": \#(startMs), "pos": 0 },
           { "seq": 3, "type": "viewEnded", "t": \#(startMs + durationMs), "pos": 0, "reason": "nav" }
         ]}
        """#
    }

    /// A View still open (no `viewEnded`) with periodic heartbeats confirming
    /// continuous playback from `startMs` through `throughMs` — how a
    /// genuinely `provisional` Segment (never wholesale-replaced yet) is
    /// produced spanning a Day boundary the hard cap forces closed.
    private func ongoingSession(viewId: String, startMs: Int, throughMs: Int, stepMs: Int = 1_800_000) -> String {
        var events = [
            #"{ "seq": 1, "type": "mediaFound", "t": \#(startMs), "pos": 0 }"#,
            #"{ "seq": 2, "type": "play", "t": \#(startMs), "pos": 0 }"#,
        ]
        var seq = 3
        var t = startMs
        while t < throughMs {
            t += stepMs
            events.append(
                #"{ "seq": \#(seq), "type": "sample", "t": \#(t), "pos": 0, "playing": true, "visible": true }"#
            )
            seq += 1
        }
        return #"""
        {"viewId":"\#(viewId)","service":"youtube","contentFormat":"standard","embedded":false,
         "videoId":"v","url":"https://example.com/v","tabId":1,"startedAt":\#(startMs),
         "adapterId":"youtube",
         "open":true,"previousViewId":null,"events":[\#(events.joined(separator: ","))]}
        """#
    }

    /// The tail closing an `ongoingSession` View, as a separate Flush (the
    /// crash-recovery / "it finally ended" arrival).
    private func endSession(viewId: String, atMs: Int) -> String {
        #"""
        {"viewId":"\#(viewId)","service":"youtube","contentFormat":"standard","embedded":false,
         "videoId":"v","url":"https://example.com/v","tabId":1,"startedAt":0,
         "adapterId":"youtube",
         "open":false,"previousViewId":null,"events":[
           { "seq": 100, "type": "viewEnded", "t": \#(atMs), "pos": 0, "reason": "nav" }
         ]}
        """#
    }

    // MARK: - Freezing writes rolled_day + rollup_slice grouped by service × contentFormat

    @Test("freezing a Day writes rollup_slice rows summed per service × contentFormat from its clipped Segments")
    func freezeWritesGroupedSlices() throws {
        let clock = ManualClock(local(2024, 1, 1, 12, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        try post(envelope(views: [
            session(viewId: "yt", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000),
            session(viewId: "nf", startMs: local(2024, 1, 1, 13, 0).epochMillis, durationMs: 120_000, service: "netflix", contentFormat: "standard", adapterId: "netflix"),
            session(viewId: "yts", startMs: local(2024, 1, 1, 14, 0).epochMillis, durationMs: 30_000, service: "youtube", contentFormat: "short", adapterId: "youtube"),
        ]), to: service, using: client)

        clock.set(local(2024, 1, 2, 4, 0)) // idle at the target hour: freezes here.
        let dayLabel = local(2024, 1, 1, 0, 0)
        let slices = try store.slices(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())

        #expect(Set(slices.map { "\($0.service)/\($0.contentFormat)" }) == ["youtube/standard", "netflix/standard", "youtube/short"])
        #expect(slices.first { $0.service == "youtube" && $0.contentFormat == "standard" }?.totals.watchedMs == 60_000)
        #expect(slices.first { $0.service == "netflix" && $0.contentFormat == "standard" }?.totals.watchedMs == 120_000)
        #expect(slices.first { $0.service == "youtube" && $0.contentFormat == "short" }?.totals.watchedMs == 30_000)

        // frozenDays() reports this Day as processed, with the sum across slices.
        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].watchedMs == 210_000)
    }

    // MARK: - Week / Month / Custom = SUM(rollup_slice) + openDayTotals()

    @Test("This Week's total equals the sum of frozen rollup_slice rows plus the live open Day")
    func weekTotalIsFrozenSlicesPlusOpenDay() throws {
        let clock = ManualClock(local(2024, 1, 1, 12, 0)) // Monday
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        try post(envelope(views: [session(viewId: "mon", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000)]), to: service, using: client)
        clock.set(local(2024, 1, 2, 4, 0)) // freezes Monday.

        clock.set(local(2024, 1, 2, 20, 0)) // Tuesday, the open Day.
        try post(envelope(views: [session(viewId: "tue", startMs: local(2024, 1, 2, 20, 0).epochMillis, durationMs: 30_000)]), to: service, using: client)
        clock.set(local(2024, 1, 2, 20, 5))

        let week = try store.totals(for: .thisWeek, now: clock.now())
        let frozenSum = try store.frozenDays().reduce(0) { $0 + $1.watchedMs }
        let openDay = try store.openDayTotals(now: clock.now())
        #expect(week.watchedMs == 90_000)
        #expect(week.watchedMs == frozenSum + openDay.watchedMs)
    }

    @Test("a frozen Day and the live open Day contributing to the same service × contentFormat merge into one slice, for Week, Month, and Custom alike")
    func mergesFrozenAndLiveContributionsToTheSameKey() throws {
        let clock = ManualClock(local(2024, 1, 1, 12, 0)) // Monday, also the 1st of the month.
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // Monday: a youtube/standard session, freezes with its own slice.
        try post(envelope(views: [session(viewId: "mon-yt", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000)]), to: service, using: client)
        clock.set(local(2024, 1, 2, 4, 0))

        // Tuesday, the open Day: another youtube/standard session (same key
        // as Monday's frozen slice) plus a distinct netflix session.
        clock.set(local(2024, 1, 2, 20, 0))
        try post(envelope(views: [
            session(viewId: "tue-yt", startMs: local(2024, 1, 2, 20, 0).epochMillis, durationMs: 30_000),
            session(viewId: "tue-nf", startMs: local(2024, 1, 2, 20, 5).epochMillis, durationMs: 10_000, service: "netflix", adapterId: "netflix"),
        ]), to: service, using: client)
        clock.set(local(2024, 1, 2, 20, 10))

        for kind in [
            DateRangeKind.thisWeek,
            .thisMonth,
            .custom(from: local(2024, 1, 1, 0, 0), through: local(2024, 1, 2, 0, 0)),
        ] {
            let slices = try store.slices(for: kind, now: clock.now())
            // Exactly one row per key — not a separate frozen-only and
            // live-only entry for youtube/standard.
            #expect(slices.filter { $0.service == "youtube" && $0.contentFormat == "standard" }.count == 1)
            #expect(slices.first { $0.service == "youtube" && $0.contentFormat == "standard" }?.totals.watchedMs == 90_000)
            #expect(slices.first { $0.service == "netflix" && $0.contentFormat == "standard" }?.totals.watchedMs == 10_000)
        }
    }

    // MARK: - Dropping both rollup tables and rebuilding

    @Test("dropping both rollup tables and rebuilding reproduces identical totals from segments")
    func rebuildReproducesIdenticalTotals() throws {
        let clock = ManualClock(local(2024, 1, 1, 12, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        try post(envelope(views: [
            session(viewId: "yt", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000),
            session(viewId: "nf", startMs: local(2024, 1, 1, 13, 0).epochMillis, durationMs: 45_000, service: "netflix", adapterId: "netflix"),
        ]), to: service, using: client)
        clock.set(local(2024, 1, 2, 4, 0))

        let dayLabel = local(2024, 1, 1, 0, 0)
        let before = try store.totals(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())
        let slicesBefore = try store.slices(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())

        try store.rebuildStatistics(now: clock.now())

        let after = try store.totals(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())
        let slicesAfter = try store.slices(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())
        #expect(after == before)
        // Both are already sorted by (service, contentFormat) — see `slices(for:)`.
        #expect(slicesAfter == slicesBefore)
    }

    // MARK: - The job skips the open Day and any Day with a provisional Segment

    @Test("the rollup job skips a Day the hard cap forced closed while its trailing Segment is still provisional")
    func skipsDayWithProvisionalSegment() throws {
        let clock = ManualClock(local(2024, 1, 3, 2, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // Still open — no viewEnded — with heartbeats confirming continuous
        // play straight through the 04:00 target hour and the 10:00 cap.
        try post(envelope(views: [
            ongoingSession(viewId: "ongoing", startMs: local(2024, 1, 3, 2, 0).epochMillis, throughMs: local(2024, 1, 3, 11, 0).epochMillis),
        ]), to: service, using: client)

        clock.set(local(2024, 1, 3, 10, 0)) // the cap: the Day boundary confirms here regardless.
        _ = try store.totals(for: .today, now: clock.now())

        // The boundary confirmed and the open Day timeline moved on, but the
        // rollup for 2024-01-03 is blocked — not "processed" yet.
        #expect(try store.frozenDays().isEmpty)

        // Once the View actually ends, a read reconciles the backlog.
        try post(envelope(views: [endSession(viewId: "ongoing", atMs: local(2024, 1, 3, 10, 0).epochMillis)]), to: service, using: client)
        _ = try store.totals(for: .today, now: clock.now())

        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].label == "2024-01-03")
        #expect(frozen[0].watchedMs == 8 * 3_600_000) // clipped to 02:00–10:00
    }

    // MARK: - App-launch reconciliation folds in a frozen Day with no rolled_day row yet processed

    @Test("relaunching folds in a Day whose rollup a lingering provisional Segment had blocked")
    func relaunchReconcilesABlockedRollup() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlogs-rollup-test-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        let clock = ManualClock(local(2024, 1, 3, 2, 0))
        do {
            let port = Int.random(in: 49_200..<52_000)
            let service = try LoopbackTransport(
                version: "0.1.0",
                tokenStore: InMemoryTokenStore(),
                store: try EventStore(path: path),
                clock: clock,
                config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
            )
            try service.start()
            let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
            try post(envelope(views: [
                ongoingSession(viewId: "ongoing", startMs: local(2024, 1, 3, 2, 0).epochMillis, throughMs: local(2024, 1, 3, 11, 0).epochMillis),
            ]), to: service, using: client)
            clock.set(local(2024, 1, 3, 10, 0))
            _ = try? service.todayTotals()
            service.stop()
            // Quits here — the View still open, its Day's rollup still blocked.
        }

        let reopened = try EventStore(path: path)
        #expect(try reopened.frozenDays().isEmpty)

        // The crash-recovery Flush lands after relaunch, finally ending the View.
        let port = Int.random(in: 49_200..<52_000)
        let relaunchedService = try LoopbackTransport(
            version: "0.1.0",
            tokenStore: InMemoryTokenStore(),
            store: reopened,
            clock: clock,
            config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        )
        try relaunchedService.start()
        defer { relaunchedService.stop() }
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(relaunchedService.boundPort))
        try post(envelope(views: [endSession(viewId: "ongoing", atMs: local(2024, 1, 3, 10, 0).epochMillis)]), to: relaunchedService, using: client)

        // Any read after relaunch reconciles the backlog.
        _ = try reopened.totals(for: .today, now: clock.now())
        let frozen = try reopened.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].watchedMs == 8 * 3_600_000)
    }

    // MARK: - schema_version mismatch triggers a rebuild of that Day

    @Test("a schema_version mismatch on a rolled_day row triggers a rebuild of that Day, picking up data written since")
    func schemaVersionMismatchRebuildsTheDay() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlogs-schema-test-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        let clock = ManualClock(local(2024, 1, 1, 12, 0))
        let dayLabel = local(2024, 1, 1, 0, 0)
        do {
            let store = try EventStore(path: path, schemaVersion: 1)
            let port = Int.random(in: 49_200..<52_000)
            let service = try LoopbackTransport(
                version: "0.1.0", tokenStore: InMemoryTokenStore(), store: store, clock: clock,
                config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
            )
            try service.start()
            let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
            try post(envelope(views: [session(viewId: "first", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000)]), to: service, using: client)
            clock.set(local(2024, 1, 2, 4, 0)) // freezes under schema_version 1.
            let frozen = try store.totals(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())
            #expect(frozen.watchedMs == 60_000)
            service.stop()
        }

        // Reopened under a bumped schema_version, with a late-arriving View
        // whose Events land inside the already-frozen Day (a crash-recovery
        // Flush for a View nobody had seen before).
        let bumped = try EventStore(path: path, schemaVersion: 2)
        let port = Int.random(in: 49_200..<52_000)
        let service = try LoopbackTransport(
            version: "0.1.0", tokenStore: InMemoryTokenStore(), store: bumped, clock: clock,
            config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        )
        try service.start()
        defer { service.stop() }
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
        try post(envelope(views: [session(viewId: "late-arrival", startMs: local(2024, 1, 1, 13, 0).epochMillis, durationMs: 30_000)]), to: service, using: client)

        // Reading under the new schema_version rebuilds the stale Day, this
        // time picking up the late arrival — proof it was actually rebuilt,
        // not left immutable as an ordinary late Flush would leave it.
        let rebuilt = try bumped.totals(for: .custom(from: dayLabel, through: dayLabel), now: clock.now())
        #expect(rebuilt.watchedMs == 90_000)
        #expect(try bumped.frozenDays().first?.watchedMs == 90_000)
    }

    // MARK: - An empty Day

    @Test("an empty Day produces a bare rolled_day row with zero rollup_slice children")
    func emptyDayProducesBareRow() throws {
        let clock = ManualClock(local(2024, 1, 1, 20, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // A Flush bootstraps the open Day at 20:00 with no watched activity at all.
        try post(envelope(views: []), to: service, using: client)
        clock.set(local(2024, 1, 2, 4, 0)) // idle at the target hour: freezes empty.

        _ = try store.totals(for: .today, now: clock.now())
        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].watchedMs == 0)
        #expect(frozen[0].backgroundMs == 0)
        #expect(try store.slices(for: .custom(from: local(2024, 1, 1, 0, 0), through: local(2024, 1, 1, 0, 0)), now: clock.now()).isEmpty)
    }

    // MARK: - totals(range, groupBy) across all four preset ranges

    @Test("slices(for:) returns watched_ms/background_ms per service × contentFormat for Today, This Week, This Month, and Custom")
    func slicesAcrossAllFourRanges() throws {
        let clock = ManualClock(local(2024, 1, 1, 12, 0)) // Monday, also the 1st of the month.
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        try post(envelope(views: [
            session(viewId: "yt", startMs: local(2024, 1, 1, 12, 0).epochMillis, durationMs: 60_000),
            session(viewId: "nf", startMs: local(2024, 1, 1, 13, 0).epochMillis, durationMs: 20_000, service: "netflix", adapterId: "netflix"),
        ]), to: service, using: client)
        clock.set(local(2024, 1, 1, 14, 0)) // after both Views ended, still the same still-open Day.

        for kind in [DateRangeKind.today, .thisWeek, .thisMonth, .custom(from: local(2024, 1, 1, 0, 0), through: local(2024, 1, 1, 0, 0))] {
            let slices = try store.slices(for: kind, now: clock.now())
            let byKey = Dictionary(uniqueKeysWithValues: slices.map { ("\($0.service)/\($0.contentFormat)", $0.totals) })
            #expect(byKey["youtube/standard"]?.watchedMs == 60_000)
            #expect(byKey["netflix/standard"]?.watchedMs == 20_000)
        }
    }

    // MARK: - "Needs an Adapter"

    @Test("Adapter.needsAdapter is true only for a null adapterId on a Service outside the shipped set")
    func needsAdapterPureFunction() {
        #expect(Adapter.needsAdapter(service: "youtube", adapterId: nil) == false)
        #expect(Adapter.needsAdapter(service: "netflix", adapterId: nil) == false)
        #expect(Adapter.needsAdapter(service: "vimeo", adapterId: nil) == true)
        #expect(Adapter.needsAdapter(service: "vimeo", adapterId: "some-adapter") == false)

        // The question is whether WatchLogs ships a reader for the platform,
        // not whether the Adapter bound on this View: `youtube.com` with a null
        // adapterId is an Adapter that failed to bind, not an Adapter to write.
        #expect(Adapter.needsAdapter(service: "youtube.com", adapterId: nil) == false)
        #expect(Adapter.needsAdapter(service: "youtu.be", adapterId: nil) == false)
    }

    @Test("a stored View with a null adapterId on a Service outside the shipped set is reported as needing an Adapter")
    func needsAdapterOnStoredView() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        try post(envelope(views: [
            session(viewId: "vimeo-view", startMs: 1_700_000_000_000, durationMs: 1000, service: "vimeo", contentFormat: "standard", adapterId: nil),
            session(viewId: "yt-view", startMs: 1_700_000_002_000, durationMs: 1000, service: "youtube", contentFormat: "standard", adapterId: "youtube"),
        ]), to: service, using: client)

        #expect(try store.needsAdapter(viewId: "vimeo-view") == true)
        #expect(try store.needsAdapter(viewId: "yt-view") == false)
        #expect(try store.needsAdapter(viewId: "no-such-view") == nil)
    }
}
