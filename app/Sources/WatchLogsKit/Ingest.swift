import Foundation

/// Turns a raw request body into an `IngestOutcome`. This is where the
/// at-least-once contract (ADR 0002) starts: a duplicate `flushId` replays its
/// stored Ack and stores nothing extra.
///
/// Lock-guarded rather than an `actor` so the loopback server can call it
/// synchronously and keep "one request in flight at a time" literally true —
/// there is no `await` point where a second request could interleave.
public final class Ingest: @unchecked Sendable {
    private let clock: Clock
    private let sink: EventSink
    private let onAccepted: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var seenFlushes: [String: Ack] = [:]

    /// Widens the critical section in tests so the "concurrent Flushes are
    /// serialised" assertion has a real race to catch. Zero in production.
    private let artificialWork: TimeInterval

    /// Test observability: the most concurrent `handle` calls ever seen inside
    /// the critical section. Must never exceed 1.
    private let concurrencyProbe = ConcurrencyProbe()

    public init(
        clock: Clock,
        sink: EventSink,
        artificialWork: TimeInterval = 0,
        onAccepted: (@Sendable () -> Void)? = nil
    ) {
        self.clock = clock
        self.sink = sink
        self.artificialWork = artificialWork
        self.onAccepted = onAccepted
    }

    public var maxObservedConcurrency: Int { concurrencyProbe.peak }

    public func handle(body: Data) -> IngestOutcome {
        lock.lock()
        defer { lock.unlock() }

        concurrencyProbe.enter()
        defer { concurrencyProbe.leave() }
        if artificialWork > 0 { Thread.sleep(forTimeInterval: artificialWork) }

        switch FlushEnvelopeDecoder.decode(body) {
        case .badRequest(let reason):
            return .badRequest(error: reason)

        case .unsupportedSchemaVersion:
            // Nothing stored — the Extension keeps the batch buffered.
            return .unsupportedSchemaVersion

        case .ok(let envelope):
            if let replayed = seenFlushes[envelope.flushId] {
                onAccepted?()
                return .accepted(replayed)
            }
            try? sink.append(flushId: envelope.flushId, views: envelope.views)
            let ack = Ack(
                flushId: envelope.flushId,
                views: envelope.views.map { view in
                    Ack.ViewAck(viewId: view.viewId, ackSeq: view.events.map(\.seq).max() ?? 0)
                },
                serverTime: clock.now().epochMillis
            )
            seenFlushes[envelope.flushId] = ack
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
