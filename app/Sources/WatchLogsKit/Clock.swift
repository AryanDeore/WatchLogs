import Foundation

/// An injectable clock. The Day boundary detector, rollups, and `openDayTotals()`
/// all need this to be testable (system spec, "Time and clock"). For issue #26 it
/// only stamps `serverTime` on an Ack, but the seam is put in place now.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// A clock the tests advance by hand.
public final class ManualClock: Clock {
    private let time: Locked<Date>

    public init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.time = Locked(start)
    }

    public func now() -> Date { time.current }

    public func advance(by interval: TimeInterval) {
        time.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    public func set(_ date: Date) { time.set(date) }
}

extension Date {
    /// Epoch milliseconds, the wire representation for all timestamps (schema v1).
    var epochMillis: Int {
        Int((timeIntervalSince1970 * 1000).rounded())
    }
}
