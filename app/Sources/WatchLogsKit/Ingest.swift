import Foundation

/// Turns a raw request body into an `IngestOutcome`.
///
/// Delivery is **at-least-once** (ADR 0002): the App keeps no memory of Flushes
/// it has already seen. A resent Flush is simply processed again and acked again;
/// downstream de-duplication on stable Event ids (slice 2) is what keeps a
/// re-delivered batch from inflating anything. For a `views: []` heartbeat a
/// resend stores nothing either way.
///
/// Lock-guarded rather than an `actor` so the loopback server can call it
/// synchronously and keep "one request in flight at a time" literally true —
/// there is no `await` point where a second request could interleave.
public final class Ingest: @unchecked Sendable {
    private let clock: Clock
    private let sink: EventSink
    private let onAccepted: (@Sendable () -> Void)?
    private let lock = NSLock()

    /// Widens the critical section so the "concurrent Flushes are serialised"
    /// test has a real race to catch. Zero in production; only the internal
    /// initializer takes it.
    private let criticalSectionPadding: TimeInterval

    private let concurrencyProbe = ConcurrencyProbe()

    public convenience init(
        clock: Clock,
        sink: EventSink,
        onAccepted: (@Sendable () -> Void)? = nil
    ) {
        self.init(clock: clock, sink: sink, criticalSectionPadding: 0, onAccepted: onAccepted)
    }

    init(
        clock: Clock,
        sink: EventSink,
        criticalSectionPadding: TimeInterval,
        onAccepted: (@Sendable () -> Void)? = nil
    ) {
        self.clock = clock
        self.sink = sink
        self.criticalSectionPadding = criticalSectionPadding
        self.onAccepted = onAccepted
    }

    /// The most concurrent `handle` calls ever seen inside the critical section.
    /// The one-request-in-flight guarantee means this must never exceed 1.
    public var maxObservedConcurrency: Int { concurrencyProbe.peak }

    public func handle(body: Data) -> IngestOutcome {
        lock.lock()
        defer { lock.unlock() }

        concurrencyProbe.enter()
        defer { concurrencyProbe.leave() }
        if criticalSectionPadding > 0 { Thread.sleep(forTimeInterval: criticalSectionPadding) }

        switch FlushEnvelopeDecoder.decode(body) {
        case .badRequest(let reason):
            return .badRequest(error: reason)

        case .unsupportedSchemaVersion:
            // Nothing stored — the Extension keeps the batch buffered.
            return .unsupportedSchemaVersion

        case .ok(let envelope):
            try? sink.append(flushId: envelope.flushId, views: envelope.views)
            let ack = Ack(
                flushId: envelope.flushId,
                // Heartbeat views are empty; per-View ackSeq lands with Segment
                // computation (slice 2).
                views: envelope.views.map { Ack.ViewAck(viewId: $0.viewId, ackSeq: 0) },
                serverTime: clock.now().epochMillis
            )
            onAccepted?()
            return .accepted(ack)
        }
    }
}

/// Tracks the peak number of threads simultaneously inside a guarded region.
private final class ConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var _peak = 0

    func enter() {
        lock.lock(); defer { lock.unlock() }
        current += 1
        _peak = max(_peak, current)
    }

    func leave() {
        lock.lock(); defer { lock.unlock() }
        current -= 1
    }

    var peak: Int {
        lock.lock(); defer { lock.unlock() }
        return _peak
    }
}
