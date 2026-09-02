import Foundation
import Testing
@testable import WatchLogsKit

/// `DayBoundary.confirmedEnd` (ADR 0001): a pure function of the Day's start,
/// the merged watched-time timeline, and "now". Every case here is a rule
/// that would be expensive to get wrong once Days are frozen — mirrors how
/// `SegmentComputationTests` exercises `SegmentComputer` directly, below the
/// HTTP seam.
@Suite("Activity-flexed Day boundary")
struct DayBoundaryTests {
    /// UTC throughout, so the fixed-clock cases don't depend on the machine
    /// running the tests. The DST suite below uses a real zone deliberately.
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func interval(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: end)
    }

    // MARK: - No activity at the target hour

    @Test("no watched activity at the target hour: the boundary is the target hour")
    func boundaryIsTargetHourWhenIdle() {
        let dayStart = date(2026, 8, 25, 4)
        let watched = [interval(date(2026, 8, 25, 20), date(2026, 8, 25, 23))]

        // Before the target hour: still open.
        #expect(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 3), calendar: utc) == nil)

        // At/after the target hour with nothing playing: confirmed immediately.
        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 4), calendar: utc)
        #expect(end == date(2026, 8, 26, 4))
    }

    @Test("a session 23:30 to 01:00 lands in one Day labelled the start date")
    func lateSessionStaysInOneDay() {
        let dayStart = date(2026, 8, 25, 4)
        let watched = [interval(date(2026, 8, 25, 23, 30), date(2026, 8, 26, 1, 0))]

        // The session ends well before the next target hour and has nothing
        // playing there, so the Day still closes at 04:00 the next morning —
        // one Day covering the whole 23:30→01:00 session, labelled Aug 25.
        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 4), calendar: utc)
        #expect(end == date(2026, 8, 26, 4))
        #expect(DayBoundary.label(for: dayStart, calendar: utc) == "2026-08-25")
    }

    // MARK: - Sliding past the target hour

    @Test("activity in progress at the target hour slides the boundary to the end of a 90-minute idle span")
    func slidesToEndOfIdleGap() {
        let dayStart = date(2026, 8, 25, 4)
        // Playing straight through 04:00, stops at 04:20, resumes at 05:00
        // (a 40-minute gap — not enough), stops for good at 05:30.
        let watched = [
            interval(date(2026, 8, 26, 3, 0), date(2026, 8, 26, 4, 20)),
            interval(date(2026, 8, 26, 5, 0), date(2026, 8, 26, 5, 30)),
        ]

        // Not yet confirmed: only 40 minutes idle since the last stop.
        #expect(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 6), calendar: utc) == nil)

        // 90 minutes after the 05:30 stop, with nothing further playing.
        let boundary = date(2026, 8, 26, 5, 30).addingTimeInterval(90 * 60)
        #expect(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: boundary, calendar: utc) == boundary)
        // Not confirmed one second before the 90 minutes are up.
        #expect(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: boundary.addingTimeInterval(-1), calendar: utc) == nil)
    }

    @Test("a gap of exactly 90 minutes between two watched spans closes at the end of that gap")
    func interiorGapClosesAtItsEnd() {
        let dayStart = date(2026, 8, 25, 4)
        let firstStop = date(2026, 8, 26, 4, 10)
        let resumeAt = firstStop.addingTimeInterval(90 * 60)
        let watched = [
            interval(date(2026, 8, 26, 3, 0), firstStop),
            interval(resumeAt, resumeAt.addingTimeInterval(600)),
        ]

        // "now" is well after the resumed span even started — the interior
        // 90-minute gap already resolved the boundary before that.
        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: resumeAt.addingTimeInterval(3600), calendar: utc)
        #expect(end == resumeAt)
    }

    // MARK: - Background audio does not hold a Day open

    @Test("background audio at the target hour does not hold the Day open")
    func backgroundAudioDoesNotSlide() {
        let dayStart = date(2026, 8, 25, 4)
        // The caller only ever passes *watched* intervals in — a background
        // stream running straight through the target hour contributes none.
        let watched: [DateInterval] = []

        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 4), calendar: utc)
        #expect(end == date(2026, 8, 26, 4))
    }

    // MARK: - The hard cap

    @Test("the 10:00 cap forces the Day closed even with activity still going")
    func hardCapForcesClosure() {
        let dayStart = date(2026, 8, 25, 4)
        // Watched, uninterrupted, from before the target hour straight
        // through the cap.
        let watched = [interval(date(2026, 8, 26, 2), date(2026, 8, 26, 12))]

        #expect(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 9, 59), calendar: utc) == nil)
        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 10), calendar: utc)
        #expect(end == date(2026, 8, 26, 10))
    }

    @Test("a slide that would land past the cap is clamped to the cap")
    func slideClampedToCap() {
        let dayStart = date(2026, 8, 25, 4)
        // Stops at 09:50 — ten minutes before the cap, nowhere near 90
        // minutes of idle before the cap fires.
        let watched = [interval(date(2026, 8, 26, 4), date(2026, 8, 26, 9, 50))]

        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 10), calendar: utc)
        #expect(end == date(2026, 8, 26, 10))
    }

    // MARK: - Relaunch into a gap

    @Test("evaluating long after the fact (an App relaunch) confirms the boundary immediately")
    func relaunchIntoGapConfirmsImmediately() {
        let dayStart = date(2026, 8, 25, 4)
        let lastStop = date(2026, 8, 26, 3, 0)
        let watched = [interval(date(2026, 8, 26, 1), lastStop)]

        // The App was quit and reopened two days later — no intermediate
        // evaluation ever happened, but the pure function still resolves
        // correctly from dayStart, the known intervals, and "now" alone.
        let relaunchNow = date(2026, 8, 28, 12)
        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: relaunchNow, calendar: utc)
        // No activity at the 04:00 target hour, so the boundary is 04:00 —
        // long since passed by the time the App relaunched.
        #expect(end == date(2026, 8, 26, 4))
    }

    // MARK: - The configurable target hour

    @Test("a configured target hour of 02:00 is honoured instead of the 04:00 default")
    func configurableTargetHour() {
        let dayStart = date(2026, 8, 25, 2)
        let watched: [DateInterval] = []

        let end = DayBoundary.confirmedEnd(
            dayStart: dayStart, watchedIntervals: watched, now: date(2026, 8, 26, 2), targetHour: 2, calendar: utc
        )
        #expect(end == date(2026, 8, 26, 2))
    }

    // MARK: - Time zone and DST stability

    @Test("the target and cap instants are evaluated in the calendar's current zone, not a cached one")
    func evaluatesInTheGivenZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let dayStart = tokyo.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 4))!
        let expectedTarget = tokyo.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 4))!

        let end = DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: [], now: expectedTarget, calendar: tokyo)
        #expect(end == expectedTarget)
    }

    @Test("a DST spring-forward transition does not break target/cap resolution")
    func dstTransitionIsHandled() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        // Clocks spring forward at 02:00 → 03:00 on 2026-03-08 in New York.
        let dayStart = newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 4))!
        let watched: [DateInterval] = []
        let now = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!

        // The boundary still resolves to *a* 04:00 the next day, without
        // crashing or producing a nonsensical instant, despite the missing
        // hour that morning.
        let end = try #require(DayBoundary.confirmedEnd(dayStart: dayStart, watchedIntervals: watched, now: now, calendar: newYork))
        let resolvedHour = newYork.component(.hour, from: end)
        #expect(resolvedHour == 4)
        #expect(newYork.isDate(end, inSameDayAs: dayStart.addingTimeInterval(86_400)))
    }
}
