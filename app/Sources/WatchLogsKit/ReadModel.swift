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

/// The four ranges the UI's shared date-range selector offers (issue #18 —
/// preset chips Today / This Week / This Month / Custom).
///
/// Range membership follows a Day's **label**, not its wall-clock end (ADR
/// 0001): a Day labelled Aug 25 that ran to 05:10 on Aug 26 is in the week of
/// Aug 25 and in August.
public enum DateRangeKind: Equatable, Sendable {
    /// The current open Day.
    case today
    /// Monday through the open Day, of the week containing the open Day's label.
    case thisWeek
    /// The 1st through the open Day, of the month containing the open Day's label.
    case thisMonth
    /// Whole Days, inclusive, by label. `through` in the future clips to the
    /// open Day.
    case custom(from: Date, through: Date)
}

/// One frozen Day (ADR 0001): its absolute, never-re-evaluated boundaries and
/// the Watched/Background totals snapshotted at freeze time, so a later,
/// out-of-order Event landing inside it cannot move its numbers.
public struct FrozenDay: Equatable, Sendable {
    /// `yyyy-MM-dd`, the calendar date the Day began — its label.
    public var label: String
    public var dayStartMs: Int
    /// Exclusive.
    public var dayEndMs: Int
    public var watchedMs: Int
    public var backgroundMs: Int
}
