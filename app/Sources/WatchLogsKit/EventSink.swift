import Foundation

/// Where accepted raw Events go. Slice 1 has no database yet, so the default sink
/// just counts what it was handed — enough for the "stores nothing on 415" and
/// "duplicate flushId isn't re-stored" assertions. The SQLite `raw_events`
/// implementation lands with Segment computation (slice 2).
public protocol EventSink: Sendable {
    /// Append every Event in `views` to the raw log. Called only for an accepted,
    /// non-duplicate Flush.
    func append(flushId: String, views: [FlushView]) throws
}

public final class InMemoryEventSink: EventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _appendCalls = 0
    private var _appendedEventCount = 0
    private var _flushIds: [String] = []

    public init() {}

    public func append(flushId: String, views: [FlushView]) throws {
        lock.lock(); defer { lock.unlock() }
        _appendCalls += 1
        _flushIds.append(flushId)
        _appendedEventCount += views.reduce(0) { $0 + $1.events.count }
    }

    public var appendCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _appendCalls
    }

    public var appendedEventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _appendedEventCount
    }

    public var flushIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return _flushIds
    }
}
