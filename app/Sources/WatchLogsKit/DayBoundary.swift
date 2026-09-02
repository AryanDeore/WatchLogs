import Foundation

/// Detects where the activity-flexed **Day** boundary falls (ADR 0001,
/// `CONTEXT.md` "Day").
///
/// Pure: the caller supplies the Day's start, the merged watched-time
/// timeline, "now", and the target hour — nothing here touches a clock or
/// storage, which is what makes the flex/freeze behaviour testable without
/// waiting real hours. The App owns the injectable clock and merges watched
/// Segments across all Views before calling in.
public enum DayBoundary {
    /// User-configurable in Settings; this is only the default.
    public static let defaultTargetHour = 4
    /// Fixed regardless of the target hour.
    public static let hardCapHour = 10
    /// The idle span that confirms a slid boundary.
    public static let idleThreshold: TimeInterval = 90 * 60

    /// `nil` while the Day is still open. A non-nil result is always `<= now`
    /// and, once returned for a given `dayStart`, must never be
    /// re-evaluated — the caller freezes it there and starts the next Day at
    /// that instant.
    public static func confirmedEnd(
        dayStart: Date,
        watchedIntervals: [DateInterval],
        now: Date,
        targetHour: Int = defaultTargetHour,
        calendar: Calendar = .current
    ) -> Date? {
        let target = nextOccurrence(strictlyAfter: dayStart, hour: targetHour, calendar: calendar)
        let cap = nextOccurrence(atOrAfter: target, hour: hardCapHour, calendar: calendar)

        if now < target { return nil }

        let merged = merge(watchedIntervals)
        let relevant = merged.filter { $0.end > target }
        guard let first = relevant.first, first.start <= target else {
            // No watched-time activity at the target hour: the boundary is
            // the target hour, full stop — activity that resumes afterward
            // starts the next Day. The cap never enters into it, however far
            // in the future "now" is (an App relaunch days later still
            // resolves this the same way).
            return target
        }

        // Activity was ongoing at the target hour: slide to the end of the
        // next 90-minute idle span, walking the merged intervals forward —
        // clipped to `[target, cap)` first, since activity beyond the cap
        // cannot rescue a slide that hasn't resolved by then and the cap
        // forces closure regardless.
        let clipped: [DateInterval] = relevant.compactMap { interval in
            let start = max(interval.start, target)
            let end = min(interval.end, cap)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }

        var cursorEnd = clipped[0].end
        for interval in clipped.dropFirst() {
            if interval.start.timeIntervalSince(cursorEnd) >= idleThreshold {
                return cursorEnd.addingTimeInterval(idleThreshold)
            }
            cursorEnd = interval.end
        }

        // No interior gap resolved it. Activity clipped straight through to
        // the cap: forced closed once "now" reaches it.
        if cursorEnd >= cap {
            return now >= cap ? cap : nil
        }

        // A trailing gap after the last known activity, still within
        // `[target, cap)`.
        let trailingEdge = min(now, cap)
        if trailingEdge.timeIntervalSince(cursorEnd) >= idleThreshold {
            return cursorEnd.addingTimeInterval(idleThreshold)
        }
        return now >= cap ? cap : nil
    }

    /// The calendar date a Day starting at `dayStart` is labelled with —
    /// `yyyy-MM-dd` in `calendar`'s time zone. Stable once the Day is frozen,
    /// since a frozen Day's `dayStart` never moves.
    public static func label(for dayStart: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    /// The earliest instant strictly after `date` whose local time-of-day is
    /// `hour:00:00`.
    static func nextOccurrence(strictlyAfter date: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )!
    }

    /// The earliest instant at or after `date` whose local time-of-day is
    /// `hour:00:00`.
    static func nextOccurrence(atOrAfter date: Date, hour: Int, calendar: Calendar) -> Date {
        if let sameDay = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date), sameDay >= date {
            return sameDay
        }
        return nextOccurrence(strictlyAfter: date, hour: hour, calendar: calendar)
    }

    /// Sort and coalesce overlapping or touching intervals so a merged span
    /// counts as one continuous run of activity — simultaneous playback in
    /// two Views must not look like alternating idle/active slivers.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                if interval.end > last.end {
                    result[result.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
