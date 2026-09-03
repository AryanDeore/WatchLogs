import AppKit
import Observation
import WatchLogsKit

/// Drives the menu-bar label image: today's watched time as the readout, and a
/// slow breathing pulse on the mark whenever a video is playing.
///
/// Two cadences. A slow `stateTimer` polls the store for the current number and
/// whether anything is playing; a fast `pulseTimer` runs only while something
/// is playing and re-renders the mark's opacity ~20×/s. Idle, the image is
/// rendered once at full opacity and left alone.
///
/// Pulse shape was chosen in `prototypes/app-icon-pulse/` (see its README
/// "Verdict"): 2.6 s cycle, mark never dips below 45% opacity, symmetric eased
/// fade, no colour, no size change.
@Observable
@MainActor
final class MenuBarIconModel {
    private(set) var icon: NSImage

    private let transport: LoopbackTransport
    private let forcePulse: Bool

    private var watchedMs = 0
    private var isPlaying = false

    private var stateTimer: Timer?
    private var pulseTimer: Timer?

    private let pulsePeriod: TimeInterval = 2.6
    private let pulseMinOpacity: Double = 0.45
    private let statePollInterval: TimeInterval = 3
    private let pulseFrameInterval: TimeInterval = 1.0 / 20.0

    /// `forcePulse` (wired to the `WATCHLOGS_FORCE_PULSE` env var) makes the
    /// pulse run without real playback data — for eyeballing the animation.
    init(transport: LoopbackTransport, forcePulse: Bool = false) {
        self.transport = transport
        self.forcePulse = forcePulse
        self.icon = .watchLogsMenuBar(watchedMs: 0, markOpacity: 1)

        refreshState()
        stateTimer = Timer.scheduledTimer(withTimeInterval: statePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    /// The timers are `[weak self]` and the model lives for the whole app
    /// session (like `MenubarPopoverReadModel`), so there is no `deinit`
    /// teardown; the run loop drops both timers at process exit.

    private func refreshState() {
        watchedMs = (try? transport.todayTotals().watchedMs) ?? watchedMs

        let playingNow = forcePulse || Self.anythingPlaying(transport)
        if playingNow != isPlaying {
            isPlaying = playingNow
            if playingNow { startPulse() } else { stopPulse() }
        }
        // Keep the number current between pulse frames (and while idle).
        if !isPlaying { render(markOpacity: 1) }
    }

    private static func anythingPlaying(_ transport: LoopbackTransport) -> Bool {
        let days = (try? transport.store.history(for: .today, now: Date())) ?? []
        return days.contains { $0.videos.contains(where: \.isPlaying) }
    }

    private func startPulse() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: pulseFrameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPulse() }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        render(markOpacity: 1)
    }

    private func tickPulse() {
        let phase = Date().timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
        // Symmetric eased triangle: 1 at the cycle ends (full), 0 at the middle.
        let triangle = abs(2 * phase - 1)
        let intensity = triangle * triangle * (3 - 2 * triangle)
        render(markOpacity: pulseMinOpacity + (1 - pulseMinOpacity) * intensity)
    }

    private func render(markOpacity: Double) {
        icon = .watchLogsMenuBar(watchedMs: watchedMs, markOpacity: markOpacity)
    }
}
