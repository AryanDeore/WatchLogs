import Foundation

/// Turns a raw request body into an `IngestOutcome`: decode the Flush, hand it to
/// the store, answer with an Ack.
///
/// Delivery is at-least-once (ADR 0002). The Extension resends a batch whose Ack
/// it never saw, reusing the same `flushId`; the store replays that Flush's
/// original Ack and stores nothing, so a resend never moves a total. Duplicate
/// Events arriving under a *new* `flushId` are stored — the log is append-only —
/// and de-duplicated on `(viewId, seq)` when Segments are recomputed.
///
/// Lock-guarded rather than an `actor` so the loopback server can call it
/// synchronously and keep "one request in flight at a time" literally true —
/// there is no `await` point where a second request could interleave.
public final class Ingest: @unchecked Sendable {
    private let clock: Clock
    private let store: EventStore
    private let onAccepted: (@Sendable () -> Void)?
    private let lock = NSLock()

    /// Widens the critical section so the "concurrent Flushes are serialised"
    /// test has a real race to catch. Zero in production; only the internal
    /// initializer takes it.
    private let criticalSectionPadding: TimeInterval

    private let concurrencyProbe = ConcurrencyProbe()

    /// Armed by `requestFlushAgain()`, consumed by the very next accepted Flush
    /// (whichever paired Extension sends it) and cleared. Guarded by `lock`
    /// like everything else `handle` touches.
    private var flushAgainRequested = false

    public convenience init(
        clock: Clock,
        store: EventStore,
        onAccepted: (@Sendable () -> Void)? = nil
    ) {
        self.init(clock: clock, store: store, criticalSectionPadding: 0, onAccepted: onAccepted)
    }

    init(
        clock: Clock,
        store: EventStore,
        criticalSectionPadding: TimeInterval,
        onAccepted: (@Sendable () -> Void)? = nil
    ) {
        self.clock = clock
        self.store = store
        self.criticalSectionPadding = criticalSectionPadding
        self.onAccepted = onAccepted
    }

    /// The most concurrent `handle` calls ever seen inside the critical section.
    /// The one-request-in-flight guarantee means this must never exceed 1.
    public var maxObservedConcurrency: Int { concurrencyProbe.peak }

    /// Arms the "flush again" hint (issue #35 §3's refresh button): the next
    /// accepted Flush's Ack carries `flushAgain: true` instead of the App's
    /// usual silent Ack, so the Extension re-flushes immediately rather than
    /// waiting for its next cadence tick.
    public func requestFlushAgain() {
        lock.lock()
        defer { lock.unlock() }
        flushAgainRequested = true
    }

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
            do {
                var ack = try store.record(envelope, serverTime: clock.now().epochMillis)
                if flushAgainRequested {
                    flushAgainRequested = false
                    ack.flushAgain = true
                }
                onAccepted?()
                return .accepted(ack)
            } catch {
                // Never ack a batch we failed to store: the Extension would prune
                // it. A 500 means "keep it and retry".
                return .storageFailure
            }
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
