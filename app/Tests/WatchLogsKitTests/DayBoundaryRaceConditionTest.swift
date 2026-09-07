import Foundation
import Testing
@testable import WatchLogsKit

/// Regression test for the 2026-09-06 bug: a segment crossing the target hour
/// arrived in a flush 36 seconds after the activity ended, racing with another
/// flush that triggered a premature boundary freeze.
@Suite("Day boundary race condition (2026-09-06 fix)")
struct DayBoundaryRaceConditionTest {
    private let localCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ sec: Int = 0) -> Date {
        localCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: sec))!
    }

    @Test("backlog check prevents freeze when activity is near target hour and might still be in flight")
    func preventsFreezeWhenActivityNearTargetHour() throws {
        let store = try EventStore(path: ":memory:")
        
        // Day starts at 04:00 on Sept 5
        let dayStartTime = date(2026, 9, 5, 4, 0, 1).epochMillis
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: "bootstrap",
                sentAt: dayStartTime,
                agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
                views: []
            ),
            serverTime: dayStartTime
        )
        
        // Critical scenario: activity that crosses the NEXT target hour (Sept 6 04:00)
        // This activity happens from 03:59:59 to 04:00:05
        let crossingStart = date(2026, 9, 6, 3, 59, 59).epochMillis
        let crossingEnd = date(2026, 9, 6, 4, 0, 5).epochMillis
        let crossingView = FlushView(
            viewId: "crossing",
            service: "youtube",
            contentFormat: "standard",
            videoId: "cross",
            url: "https://youtube.com/watch?v=cross",
            durationSec: 600,
            adapterId: "youtube",
            tabId: 1,
            startedAt: crossingStart,
            open: false,
            events: [
                RawEvent(seq: 1, type: .play, t: crossingStart, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: crossingEnd, pos: 6, reason: "nav")
            ]
        )
        
        // Activity after the target that doesn't cross it
        let afterStart = date(2026, 9, 6, 4, 0, 20).epochMillis
        let afterView = FlushView(
            viewId: "after",
            service: "youtube",
            contentFormat: "standard",
            videoId: "after",
            url: "https://youtube.com/watch?v=after",
            durationSec: 600,
            adapterId: "youtube",
            tabId: 2,
            startedAt: afterStart,
            open: false,
            events: [
                RawEvent(seq: 1, type: .play, t: afterStart, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: afterStart + 10_000, pos: 10, reason: "nav")
            ]
        )
        
        // Race condition: the "after" flush arrives at 04:00:31, BEFORE the crossing flush
        let flushAt04_00_31 = date(2026, 9, 6, 4, 0, 31).epochMillis
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: "after-flush",
                sentAt: flushAt04_00_31,
                agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
                views: [afterView]
            ),
            serverTime: flushAt04_00_31
        )
        
        // At this point, WITHOUT THE FIX, the day would freeze at 04:00
        // because the backlog check wouldn't see the crossing segment yet.
        // WITH THE FIX, it should detect activity near the boundary and wait.
        let afterFirstFlush = try store.activityDay(now: Date(epochMillis: flushAt04_00_31), calendar: localCalendar)
        let expectedDayStart = date(2026, 9, 5, 4, 0, 1)
        #expect(afterFirstFlush == expectedDayStart, "Day should still be open after first flush")
        
        // Now the crossing flush arrives
        let flushAt04_00_36 = date(2026, 9, 6, 4, 0, 36).epochMillis
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: "crossing-flush",
                sentAt: flushAt04_00_36,
                agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
                views: [crossingView]
            ),
            serverTime: flushAt04_00_36
        )
        
        // Day should STILL not be frozen (within the 90-minute window)
        let afterCrossingFlush = try store.activityDay(now: Date(epochMillis: flushAt04_00_36), calendar: localCalendar)
        #expect(afterCrossingFlush == expectedDayStart, "Day should still be open after crossing flush arrives")
        
        // Fast forward to 90 minutes after the latest near-target activity
        // ended. `afterView` ends at 04:00:30, so the slid boundary confirms at
        // 05:30:30.
        let afterSlideWindow = date(2026, 9, 6, 5, 30, 31).epochMillis
        let frozenStart = try store.activityDay(now: Date(epochMillis: afterSlideWindow), calendar: localCalendar)

        // NOW the day should have slid and frozen.
        let expectedBoundary = date(2026, 9, 6, 5, 30, 30)
        #expect(frozenStart == expectedBoundary, "New day should start at the slid boundary")
        
        // Verify the frozen day
        let frozen = try store.frozenDays()
        #expect(frozen.count == 1)
        let day = try #require(frozen.first)
        #expect(day.dayStartMs == expectedDayStart.epochMillis)
        #expect(day.dayEndMs == expectedBoundary.epochMillis)
    }
    
    @Test("activity far from target hour freezes normally without delay")
    func normalFreezeWhenActivityNotNearBoundary() throws {
        let store = try EventStore(path: ":memory:")
        
        // Day starts at 04:00 on Sept 5
        let dayStartTime = date(2026, 9, 5, 4, 0, 1).epochMillis
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: "bootstrap",
                sentAt: dayStartTime,
                agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
                views: []
            ),
            serverTime: dayStartTime
        )
        
        // Activity at 20:00 (8 PM) - nowhere near the 04:00 target
        let viewStart = date(2026, 9, 5, 20, 0, 0).epochMillis
        let view = FlushView(
            viewId: "evening",
            service: "youtube",
            contentFormat: "standard",
            videoId: "v1",
            url: "https://youtube.com/watch?v=v1",
            durationSec: 600,
            adapterId: "youtube",
            tabId: 1,
            startedAt: viewStart,
            open: false,
            events: [
                RawEvent(seq: 1, type: .play, t: viewStart, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: viewStart + 60_000, pos: 60, reason: "nav")
            ]
        )
        
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: "evening-flush",
                sentAt: viewStart + 60_000,
                agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
                views: [view]
            ),
            serverTime: viewStart + 60_000
        )
        
        // Jump to 04:00 the next day - activity ended 8 hours ago, way past the 3-minute threshold
        let nextTarget = date(2026, 9, 6, 4, 0, 0).epochMillis
        let openStart = try store.activityDay(now: Date(epochMillis: nextTarget), calendar: localCalendar)
        
        // Should freeze immediately at the target hour (no activity at target)
        #expect(openStart == date(2026, 9, 6, 4, 0, 0), "Should freeze at target hour immediately")
    }
}
