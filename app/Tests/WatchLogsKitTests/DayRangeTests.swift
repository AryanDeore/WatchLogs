import Foundation
import Testing
@testable import WatchLogsKit

/// The activity-flexed Day wired into the App read model (ADR 0001, issue
/// #21): real Flush bodies in over `POST /v1/flush`, an injected clock
/// advanced by hand, `EventStore.totals(for:)` and `frozenDays()` out.
/// Complements `DayBoundaryTests`, which exercises the pure detector below
/// this seam.
@Suite("Day-aware ranges and freeze", .serialized)
struct DayRangeTests {
    private func post(_ body: Data, to service: LoopbackTransport, using client: RawHTTPClient) throws {
        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(service.pairing().token)", "Content-Type": "application/json"],
            body: body
        )
        #expect(response.status == 200)
    }

    /// A fixed, unambiguous calendar date so the tests don't depend on which
    /// day of the week the suite happens to run. 2024-01-01 is a Monday,
    /// 2023-12-31 the Sunday before it (previous week *and* previous month).
    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    /// One View, watched continuously from `startMs` for `durationMs` — just
    /// `play` then `viewEnded`, no gaps, for a session long enough to run
    /// straight through the target hour and the 10:00 cap.
    private func continuousSession(startMs: Int, durationMs: Int) -> Data {
        let events = [
            #"{ "seq": 1, "type": "mediaFound", "t": \#(startMs), "pos": 0 }"#,
            #"{ "seq": 2, "type": "play", "t": \#(startMs), "pos": 0 }"#,
            #"{ "seq": 3, "type": "viewEnded", "t": \#(startMs + durationMs), "pos": 0, "reason": "nav" }"#,
        ]
        return FlushJSON.envelope(views: [FlushJSON.view(id: "view-continuous-\(startMs)", open: false, events: events)])
    }

    // MARK: - The hard cap

    @Test("the 10:00 cap forces the Day closed through the full seam, even with a Segment still playing past it")
    func hardCapFreezesThroughTheFullSeam() throws {
        let clock = ManualClock(local(2024, 1, 3, 2, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // The open Day bootstraps at 02:00 and this one View plays straight
        // through both the 04:00 target hour and the 10:00 cap, ending at 11:00.
        try post(continuousSession(startMs: local(2024, 1, 3, 2, 0).epochMillis, durationMs: 9 * 3600 * 1000), to: service, using: client)

        let totals = try store.totals(for: .today, now: local(2024, 1, 3, 10, 0))
        #expect(totals.watchedMs == 0) // the *new* open Day, starting fresh at the cap

        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].label == "2024-01-03")
        #expect(frozen[0].dayStartMs == local(2024, 1, 3, 2, 0).epochMillis)
        #expect(frozen[0].dayEndMs == local(2024, 1, 3, 10, 0).epochMillis) // the cap, not the Segment's real end
        // Clipped to the frozen window: 02:00–10:00, not the full 9 h Segment.
        #expect(frozen[0].watchedMs == 8 * 3_600_000)

        // The remaining hour (10:00–11:00) rolls into the new open Day —
        // clipped, never cut, never dropped.
        let nextDayTotals = try store.totals(for: .today, now: local(2024, 1, 3, 11, 0))
        #expect(nextDayTotals.watchedMs == 3_600_000)
    }

    // MARK: - Freeze immutability

    @Test("once frozen, a Day's totals do not change when a later out-of-band Flush lands inside it")
    func frozenDayIsImmutableToLateArrivals() throws {
        let clock = ManualClock(local(2024, 1, 1, 20, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // The store's very first Flush bootstraps the open Day at 20:00.
        try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 1, 20, 0).epochMillis), to: service, using: client)

        // Nothing else plays; the next evaluation at/after the 04:00 target
        // hour confirms and freezes the Day there — no further Flush needed,
        // the same as an App relaunch confirming a boundary on its first read.
        clock.set(local(2024, 1, 2, 4, 0))
        let beforeLateArrival = try store.totals(for: .today, now: clock.now())
        #expect(beforeLateArrival.watchedMs == 0) // the new open Day, so far empty

        var frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].label == "2024-01-01")
        #expect(frozen[0].watchedMs == 60_000)

        // A crash-recovery Flush for a View nobody had seen before arrives
        // hours later, with Events timestamped inside the now-frozen Day.
        try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 1, 21, 0).epochMillis), to: service, using: client)

        frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].watchedMs == 60_000) // unchanged — not 120_000

        let rangeTotals = try store.totals(for: .custom(from: local(2024, 1, 1, 12, 0), through: local(2024, 1, 1, 12, 0)), now: clock.now())
        #expect(rangeTotals.watchedMs == 60_000)
    }

    @Test("relaunching the App into an idle gap past the target hour confirms and freezes the previous Day")
    func relaunchIntoGapFreezesThePreviousDay() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlogs-day-test-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        let clock = ManualClock(local(2024, 1, 1, 20, 0))
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
            try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 1, 20, 0).epochMillis), to: service, using: client)
            service.stop()
            // The App quits here — nothing evaluates the Day boundary again
            // until the next launch, possibly days later.
        }

        let reopened = try EventStore(path: path)
        let relaunchNow = local(2024, 1, 5, 9, 0)
        let totals = try reopened.totals(for: .today, now: relaunchNow)
        #expect(totals.watchedMs == 0) // the reopened open Day, freshly caught up, is empty

        // The Day holding the actual activity confirms and freezes on this
        // first read after relaunch — with no watched activity at any of the
        // intervening target hours, the empty Days in between cascade closed
        // the same way (each is its own bare, zero-total frozen Day) rather
        // than staying open indefinitely.
        let frozen = try reopened.frozenDays()
        #expect(frozen.first?.label == "2024-01-01")
        #expect(frozen.first?.watchedMs == 60_000)
        #expect(frozen.first?.dayEndMs == local(2024, 1, 2, 4, 0).epochMillis) // the 04:00 target hour, not the relaunch time
        #expect(frozen.dropFirst().allSatisfy { $0.watchedMs == 0 })

        // No data lost or inflated across the whole catch-up.
        let everything = try reopened.totals(for: .custom(from: local(2024, 1, 1, 0, 0), through: relaunchNow), now: relaunchNow)
        #expect(everything.watchedMs == 60_000)
    }

    // MARK: - Week / Month membership follows a Day's label

    @Test("a Day labelled Monday but running past midnight counts in that week and month, not the day before")
    func rangeMembershipFollowsTheLabel() throws {
        let clock = ManualClock(local(2023, 12, 31, 12, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        // Day 0: Sunday Dec 31 — the previous week *and* previous month.
        try post(FlushJSON.oneMinuteSession(startingAt: local(2023, 12, 31, 12, 0).epochMillis), to: service, using: client)
        clock.set(local(2024, 1, 1, 4, 0)) // idle at the target hour: Day 0 freezes here, labelled Dec 31.

        // Day A: starts when Day 0 closes (Jan 1, 04:00), but its only
        // activity straddles midnight into Jan 2 — still labelled Jan 1.
        clock.set(local(2024, 1, 1, 23, 59, 30))
        try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 1, 23, 59, 30).epochMillis), to: service, using: client)
        clock.set(local(2024, 1, 2, 4, 0)) // idle at the target hour: Day A freezes here, labelled Jan 1.

        // Day B: the current open Day, starting Jan 2 04:00.
        clock.set(local(2024, 1, 2, 20, 0))
        try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 2, 20, 0).epochMillis), to: service, using: client)
        clock.set(local(2024, 1, 2, 20, 5))

        let frozen = try store.frozenDays()
        #expect(frozen.map(\.label) == ["2023-12-31", "2024-01-01"])
        // Day A starts the instant Day 0 froze (04:00), not when its first
        // activity happened — a Day can sit idle before any watching starts.
        #expect(frozen[1].dayStartMs == local(2024, 1, 1, 4, 0).epochMillis)
        #expect(frozen[1].dayEndMs == local(2024, 1, 2, 4, 0).epochMillis)

        // This Week (Mon Jan 1 – Sun Jan 7): Day A + the open Day B, not Day 0.
        let week = try store.totals(for: .thisWeek, now: clock.now())
        #expect(week.watchedMs == 120_000)

        // This Month (January): same two Days, not December's Day 0.
        let month = try store.totals(for: .thisMonth, now: clock.now())
        #expect(month.watchedMs == 120_000)

        // A whole-day Custom range naming only the frozen Day A.
        let justDayA = try store.totals(for: .custom(from: local(2024, 1, 1, 0, 0), through: local(2024, 1, 1, 0, 0)), now: clock.now())
        #expect(justDayA.watchedMs == 60_000)

        // Custom through today runs through the open Day, same as the week/month total here.
        let throughToday = try store.totals(
            for: .custom(from: local(2024, 1, 1, 0, 0), through: local(2024, 1, 2, 0, 0)),
            now: clock.now()
        )
        #expect(throughToday.watchedMs == 120_000)
    }

    // MARK: - Settings: the target hour

    @Test("a configured target hour takes effect for the open Day")
    func configuredTargetHourAppliesToTheOpenDay() throws {
        let clock = ManualClock(local(2024, 1, 1, 20, 0))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        try store.setTargetHour(1)
        #expect(try store.targetHour() == 1)

        try post(FlushJSON.oneMinuteSession(startingAt: local(2024, 1, 1, 20, 0).epochMillis), to: service, using: client)

        // Not yet 01:00: still open.
        clock.set(local(2024, 1, 2, 0, 59))
        _ = try store.totals(for: .today, now: clock.now())
        #expect(try store.frozenDays().isEmpty)

        // 01:00, idle: frozen there, not at the 04:00 default.
        clock.set(local(2024, 1, 2, 1, 0))
        _ = try store.totals(for: .today, now: clock.now())
        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        #expect(frozen[0].dayEndMs == local(2024, 1, 2, 1, 0).epochMillis)

        // Changing the setting afterward never moves the Day already frozen.
        try store.setTargetHour(4)
        _ = try store.totals(for: .today, now: local(2024, 1, 2, 2, 0))
        #expect(try store.frozenDays()[0].dayEndMs == local(2024, 1, 2, 1, 0).epochMillis)
    }
}
