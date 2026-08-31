import Foundation

/// Where accepted raw Events go. Slice 1 has no database yet, so the default sink
/// just counts what it was handed — enough for the "stores nothing on 415"
/// assertion. The SQLite `raw_events` implementation lands with Segment
/// computation (slice 2).
public protocol EventSink: Sendable {
    /// Append every Event in `views` to the raw log. Called only for an accepted
    /// Flush.
    func append(flushId: String, views: [FlushView]) throws
}

public final class InMemoryEventSink: EventSink {
    public struct Record: Sendable {
        public var appendCalls = 0
        public var viewCount = 0
        public var flushIds: [String] = []
    }

    private let state = Locked(Record())

    public init() {}

    public func append(flushId: String, views: [FlushView]) throws {
        state.withLock {
            $0.appendCalls += 1
            $0.viewCount += views.count
            $0.flushIds.append(flushId)
        }
    }

    public var appendCalls: Int { state.current.appendCalls }
    public var appendedViewCount: Int { state.current.viewCount }
    public var flushIds: [String] { state.current.flushIds }
}
