import Foundation

/// A value guarded by a lock. One place for the "lock, touch, unlock" dance that
/// the token holder, the bind handshake, the last-flush timestamp, and the
/// in-memory test doubles all need.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var current: Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    /// Read-modify-write under the lock; returns whatever the body returns.
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
