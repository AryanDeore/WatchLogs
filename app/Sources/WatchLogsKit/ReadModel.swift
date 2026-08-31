import Foundation

/// A half-open wall-clock window `[startMs, endMs)` in epoch milliseconds — what
/// every read of the read model is scoped by.
///
/// Timestamps are stored as UTC epoch-ms and only converted to the Mac's current
/// zone here, when a window is built.
public struct DateRange: Equatable, Sendable {
    public var startMs: Int
    /// Exclusive.
    public var endMs: Int

    public init(startMs: Int, endMs: Int) {
        self.startMs = startMs
        self.endMs = endMs
    }

    /// The naive local calendar day containing `date`.
    ///
    /// Deliberately naive: WatchLogs's real **Day** flexes with the user's
    /// activity (ADR 0001), so a session running 23:00 → 02:00 belongs to one Day
    /// labelled by its start date. That boundary detector is slice 4's job; until
    /// it lands, "today" is midnight to midnight and a late-night session splits.
    public static func day(containing date: Date, calendar: Calendar = .current) -> DateRange {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateRange(startMs: start.epochMillis, endMs: end.epochMillis)
    }
}

/// Watched time and Background audio over some range, in milliseconds.
///
/// Milliseconds all the way through: sums are exact and the single rounding to
/// whole seconds happens here, at the end, never per Segment (ADR 0003).
public struct Totals: Equatable, Sendable {
    public var watchedMs: Int
    public var backgroundMs: Int

    public init(watchedMs: Int = 0, backgroundMs: Int = 0) {
        self.watchedMs = watchedMs
        self.backgroundMs = backgroundMs
    }

    public var watchedSeconds: Int { Totals.seconds(watchedMs) }
    public var backgroundSeconds: Int { Totals.seconds(backgroundMs) }

    static func seconds(_ milliseconds: Int) -> Int {
        Int((Double(milliseconds) / 1000).rounded())
    }
}
