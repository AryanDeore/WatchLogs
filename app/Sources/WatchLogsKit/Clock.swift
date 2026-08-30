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
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }

    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        current = date
    }
}

extension Date {
    /// Epoch milliseconds, the wire representation for all timestamps (schema v1).
    var epochMillis: Int {
        Int((timeIntervalSince1970 * 1000).rounded())
    }
}
