import Foundation
import WatchLogsKit

/// Shared "ask every paired Extension to flush right now, then notice when
/// one does" logic (issue #35 §3), behind both the title row's refresh
/// button and opening the popover.
///
/// The App has no push channel to the Extension, so `LoopbackTransport
/// .requestFlushAgain()` only arms a hint the Extension's next Ack carries.
/// Everything here is about the App side of that wait: fire the hint, then
/// notice — without making the caller wait for it. `request` returns
/// immediately every time; whatever is already on screen renders at once,
/// and `onSettled` runs later, if and when there is something to say.
///
/// A bounded `for` loop over `Task.sleep`, not a repeating `Timer`: a `Timer`
/// scheduled on the default run loop can go quiet while AppKit is running
/// the popover's own event-tracking loop and never come back — which once
/// left the refresh button stuck mid-spin, disabled, with no way to retry.
/// `Task.sleep` runs on Swift Concurrency's own clock, and the loop's
/// iteration cap is the timeout, so there is no "the timer forgot to fire"
/// failure mode to have.
@MainActor
enum FlushCatchUp {
    // 8s, not 5: a lively tab's own heartbeat cadence is every 5s on its own
    // clock, unrelated to when this was called, so a click landing right
    // after one already fired can need nearly the full 5s for the next —
    // plus however long that heartbeat takes to reach the App. A poll window
    // equal to the cadence it's racing loses that race close to half the
    // time; this leaves real margin instead of being exact and fragile.
    private static let pollAttempts = 32
    private static let pollInterval: Duration = .milliseconds(250)

    /// Arms the hint and polls the store directly for a Flush newer than the
    /// one already on record when this was called. Calls `onSettled(true)`
    /// the moment one lands, or `onSettled(false)` after ~8s of nothing —
    /// once, exactly, unless the returned Task is cancelled first (in which
    /// case neither ever runs).
    ///
    /// Returns `nil` without arming anything or calling `onSettled` at all
    /// when no Extension has ever paired — there is nothing to ask.
    @discardableResult
    static func request(
        transport: LoopbackTransport,
        onSettled: @escaping @MainActor (_ caughtUp: Bool) -> Void
    ) -> Task<Void, Never>? {
        guard let before = try? transport.store.lastFlushAt() else { return nil }
        transport.requestFlushAgain()

        return Task { @MainActor in
            for _ in 0..<pollAttempts {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled { return }
                if let landed = try? transport.store.lastFlushAt(), landed > before {
                    onSettled(true)
                    return
                }
            }
            if !Task.isCancelled { onSettled(false) }
        }
    }
}
