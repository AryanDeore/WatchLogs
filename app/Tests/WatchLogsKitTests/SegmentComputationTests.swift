import Foundation
import Testing
@testable import WatchLogsKit

/// The Segment state machine (ADR 0003), driven the way the App drives it: a
/// whole View log in, Segments out. Every case here is a rule that would be
/// expensive to get wrong once Segments are stored.
@Suite("Segment computation")
struct SegmentComputationTests {
    private let viewId = "view-1"

    private func segments(_ log: EventLogBuilder) -> [Segment] {
        SegmentComputer.segments(viewId: viewId, events: log.events)
    }

    // MARK: - Wall clock, not media time

    @Test("60 s of wall clock at 2× is 60 s of Watched time")
    func doubleRateStillCountsWallClock() {
        var log = EventLogBuilder()
        log.mediaFound(0)
        log.play(0, pos: 0)
        log.ratechange(1_000, rate: 2.0, pos: 1.0)
        for second in stride(from: 5_000, through: 55_000, by: 5_000) {
            log.sample(second, pos: Double(second) / 500)
        }
        log.viewEnded(60_000, reason: "nav", pos: 120)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].kind == .watched)
        #expect(computed[0].durationMs == 60_000)
        // 120 s of media consumed in 60 s of real time — the media range records
        // the 2×, the Watched time does not.
        #expect(computed[0].posEnd == 120)
    }

    // MARK: - Seeks

    @Test("a backward seek yields two Segments over the re-watched range, both counting")
    func backwardSeekCountsTwice() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        log.seeked(10_000, from: 10, to: 5)
        log.sample(15_000, pos: 10)
        log.viewEnded(20_000, reason: "nav", pos: 15)

        let computed = segments(log)
        #expect(computed.count == 2)
        #expect(computed.allSatisfy { $0.kind == .watched })
        // The 5 s → 10 s stretch is covered twice and counts twice.
        #expect(computed[0].posStart == 0)
        #expect(computed[0].posEnd == 10)
        #expect(computed[1].posStart == 5)
        #expect(computed[1].posEnd == 15)
        #expect(computed.reduce(0) { $0 + $1.durationMs } == 20_000)
        // No wall-clock gap: the split is instantaneous.
        #expect(computed[0].wallEndMs == computed[1].wallStartMs)
    }

    @Test("a forward seek leaves the skipped range covered by no Segment")
    func forwardSeekSkipsARange() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.seeked(6_000, from: 6, to: 100)
        log.sample(11_000, pos: 105)
        log.viewEnded(12_000, reason: "nav", pos: 106)

        let computed = segments(log)
        #expect(computed.count == 2)
        #expect(computed[0].posEnd == 6)
        #expect(computed[1].posStart == 100)
        // 6 s → 100 s of the video is inside no Segment at all.
        let covers = { (position: Double) in
            computed.contains { ($0.posStart ?? 0) <= position && position <= ($0.posEnd ?? 0) }
        }
        #expect(!covers(50))
        #expect(covers(3))
        #expect(covers(103))
    }

    @Test("Segments shorter than 1000 ms after seek-splitting are discarded")
    func noiseFloorDiscardsSlivers() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        // Two quick scrubs: 400 ms and 500 ms of playback, both below the floor.
        log.seeked(400, from: 0.4, to: 30)
        log.seeked(900, from: 30.5, to: 60)
        log.sample(5_000, pos: 64)
        log.viewEnded(6_000, reason: "nav", pos: 65)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].posStart == 60)
        #expect(computed[0].durationMs == 5_100)
    }

    // MARK: - Foreground, background, PiP

    @Test("playing while hidden accrues background only")
    func hiddenTabAccruesBackgroundOnly() {
        var log = EventLogBuilder()
        log.mediaFound(0)
        log.hidden(0)
        log.play(1_000, pos: 0)
        log.sample(6_000, playing: true, visible: false, pos: 5)
        log.sample(11_000, playing: true, visible: false, pos: 10)
        log.viewEnded(11_000, reason: "tab-closed", pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].kind == .background)
        #expect(computed[0].durationMs == 10_000)
    }

    @Test("losing the foreground splits watched into background with no wall-clock gap")
    func hiddenSplitsTheSegment() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.hidden(7_000, pos: 7)
        log.sample(12_000, playing: true, visible: false, pos: 12)
        log.viewEnded(12_000, reason: "tab-closed", pos: 12)

        let computed = segments(log)
        #expect(computed.map(\.kind) == [.watched, .background])
        #expect(computed[0].durationMs == 7_000)
        #expect(computed[1].durationMs == 5_000)
        #expect(computed[0].wallEndMs == computed[1].wallStartMs)
    }

    @Test("Picture-in-Picture keeps a hidden tab's playback Watched")
    func pipCountsAsForeground() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.pipEnter(1_000, pos: 1)
        log.hidden(2_000, pos: 2)
        log.sample(7_000, playing: true, visible: false, pos: 7)
        log.viewEnded(10_000, reason: "nav", pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].kind == .watched)
        #expect(computed[0].durationMs == 10_000)
    }

    @Test("leaving PiP with the tab still hidden drops the rest to background")
    func pipLeaveWhileHiddenBecomesBackground() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.pipEnter(0, pos: 0)
        log.hidden(1_000, pos: 1)
        log.sample(5_000, playing: true, visible: false, pos: 5)
        log.pipLeave(6_000, pos: 6)
        log.sample(11_000, playing: true, visible: false, pos: 11)
        log.viewEnded(11_000, reason: "tab-closed", pos: 11)

        let computed = segments(log)
        #expect(computed.map(\.kind) == [.watched, .background])
        #expect(computed[0].durationMs == 6_000)
        #expect(computed[1].durationMs == 5_000)
    }

    // MARK: - Conservative loss-bounding

    @Test("a missing pause closes the Segment at the last confirming sample")
    func missingPauseClosesAtLastConfirmation() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        // The `pause` Event never arrived; this heartbeat only reveals the stop.
        log.sample(15_000, playing: false, pos: 10)
        log.viewEnded(16_000, reason: "nav", pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].durationMs == 10_000)
        #expect(computed[0].posEnd == 10)
    }

    /// The shape a dead network leaves behind: `play` landed, then every
    /// heartbeat for half an hour reported the media stopped at position 0. The
    /// Extension used to call that playing (`paused` was false the whole time)
    /// and it banked 31 minutes of time for a video that never showed a frame.
    /// Whichever side regresses, the total has to stay at nothing.
    @Test("a player that never advances banks no time at all")
    func stalledPlaybackBanksNothing() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        for beat in 1...360 {
            log.sample(beat * 5_000, playing: false, pos: 0)
        }
        log.viewEnded(1_805_000, reason: "nav", pos: 0)

        #expect(segments(log).isEmpty)
    }

    /// The marimo shape: `play` landed, the log carries heartbeats (so the
    /// player was reporting in generally), but then nothing for 74 minutes
    /// because the Mac slept — and a `seek` finally revealed the media had
    /// crept only from 0 s to ~8 s the whole time. That 74-minute gap is a
    /// stall: only its media advance, plus a buffering margin, is banked.
    @Test("a stall no heartbeat bridged is clawed back to the media advance")
    func stallWithoutHeartbeatIsClawedBack() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.seeked(74 * 60_000, from: 7.7, to: 7.9)
        log.sample(74 * 60_000 + 5_000, pos: 12.9)
        log.viewEnded(74 * 60_000 + 10_000, reason: "nav", pos: 17.9)

        let computed = segments(log)
        // ~7.9 s of media advance + 60 s grace ≈ 68 s, not 74 minutes.
        #expect(computed.first?.durationMs == 67_900)
        #expect(computed.first?.posEnd == 7.7)
    }

    /// The real marimo shape (not the sparse-heartbeat one below): `play`
    /// landed, then nothing at all — no `sample` ever arrived, because the tab
    /// sat backgrounded/asleep all night — until a `viewEnded` twelve hours
    /// later revealed the media position had never left 0. A log with zero
    /// heartbeats used to get a free pass around the stall backstop entirely;
    /// it must be clawed back exactly like a heartbeat-bridged stall is.
    @Test("a stall with no heartbeat at all is clawed back the same as one a heartbeat bridges")
    func stallWithZeroHeartbeatsIsClawedBack() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.viewEnded(12 * 60 * 60_000, reason: "nav", pos: 0)

        let computed = segments(log)
        // No media advance at all + 60 s grace, not 12 hours.
        #expect(computed.first?.durationMs == 60_000)
    }

    /// A hidden tab Chromium has throttled to one timer per minute still beats,
    /// just rarely. What tells that apart from a suspended frame is the media
    /// clock keeping pace with the wall clock, so a sparse heartbeat that
    /// carries real, advancing positions counts in full however far apart the
    /// beats are.
    @Test("a sparse heartbeat whose media keeps pace is trusted as continuous playback")
    func sparseHeartbeatKeepingPaceIsTrusted() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        for beat in 1...4 {
            log.sample(beat * 30 * 60_000, pos: Double(beat) * 30 * 60)
        }
        log.viewEnded(120 * 60_000, reason: "nav", pos: 120 * 60)

        #expect(segments(log).first?.durationMs == 120 * 60_000)
    }

    /// The lid-close shape, and the reason a `sample` earns no exemption from
    /// the stall backstop. The Extension's 5-second timer does not run while the
    /// Mac sleeps; it resumes on wake, so the first Event after a four-hour nap
    /// is an ordinary heartbeat reporting `playing` at the position it left off.
    /// Trusting it because it is a heartbeat banked the whole four hours.
    @Test("a heartbeat resuming after a sleep does not vouch for the sleep")
    func heartbeatResumingAfterSleepIsClawedBack() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        // --- the lid is shut for four hours; the media clock never moves ---
        log.sample(4 * 3_600_000 + 10_000, pos: 10)
        log.viewEnded(4 * 3_600_000 + 15_000, reason: "nav", pos: 15)

        // 10 s watched + the 60 s of grace the motionless gap is credited + the
        // 5 s after the wake — not 4 h 0 m 15 s.
        #expect(segments(log).first?.durationMs == 75_000)
    }

    /// The same nap, but with the Extension doing its own job (issue #32): it
    /// notices the missed beats on wake, pauses the View back at the last beat
    /// that ran and plays it again now. Two honest Segments, and the read-side
    /// backstop never has to fire.
    @Test("an Extension that closes its own suspension gap yields two clean Segments")
    func extensionReportedSuspensionSplitsTheView() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        log.pause(10_000, pos: 10) // stamped at the last beat, not at wake
        log.play(4 * 3_600_000 + 10_000, pos: 10)
        log.sample(4 * 3_600_000 + 15_000, pos: 15)
        log.viewEnded(4 * 3_600_000 + 20_000, reason: "nav", pos: 20)

        #expect(segments(log).map(\.durationMs) == [10_000, 10_000])
    }

    @Test("slow-motion playback is wall-clock time, not clawed back")
    func slowPlaybackKeepsWallClock() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.ratechange(1_000, rate: 0.5, pos: 0.5)
        for second in stride(from: 5_000, through: 55_000, by: 5_000) {
            log.sample(second, pos: Double(second) / 2_000)
        }
        log.viewEnded(60_000, reason: "nav", pos: 30)

        let computed = segments(log)
        #expect(computed.count == 1)
        // 30 s of media in 60 s of real time at 0.5× — still 60 s Watched.
        #expect(computed[0].durationMs == 60_000)
    }

    @Test("a missing hidden splits at the last confirming sample and reopens at the revealing one")
    func missingHiddenExcludesTheUncertainGap() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        // No `hidden` Event: this heartbeat is the first news of it.
        log.sample(10_000, playing: true, visible: false, pos: 10)
        log.sample(15_000, playing: true, visible: false, pos: 15)
        log.viewEnded(15_000, reason: "tab-closed", pos: 15)

        let computed = segments(log)
        #expect(computed.map(\.kind) == [.watched, .background])
        // The 5 s → 10 s window could have been either; it counts for neither.
        #expect(computed[0].wallStartMs == log.at(0))
        #expect(computed[0].wallEndMs == log.at(5_000))
        #expect(computed[1].wallStartMs == log.at(10_000))
        #expect(computed[1].wallEndMs == log.at(15_000))
    }

    @Test("a resumed-by-heartbeat playback starts at the sample that first confirmed it")
    func revealedResumeStartsAtTheSample() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.pause(2_000, pos: 2)
        // The `play` Event never arrived.
        log.sample(10_000, playing: true, pos: 8)
        log.sample(15_000, playing: true, pos: 13)
        log.viewEnded(15_000, reason: "nav", pos: 13)

        let computed = segments(log)
        #expect(computed.map(\.durationMs) == [2_000, 5_000])
        #expect(computed[1].wallStartMs == log.at(10_000))
    }

    @Test("a crash-recovered viewEnded closes the tail at the last sample")
    func crashRecoveredClosesAtLastSample() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        // The Extension stamps the recovered end at the last sample; even a
        // stamp of "now", hours later, must not extrapolate the tail.
        log.viewEnded(3_600_000, reason: "crash-recovered", pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].wallEndMs == log.at(10_000))
        #expect(computed[0].durationMs == 10_000)
        #expect(!computed[0].provisional)
    }

    // MARK: - Open Views

    @Test("the trailing Segment of an open View is provisional and stops at the last sample")
    func openViewTailIsProvisional() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].provisional)
        #expect(computed[0].wallEndMs == log.at(10_000))
    }

    @Test("a closed View has no provisional Segment")
    func closedViewIsFinal() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.viewEnded(6_000, reason: "nav", pos: 6)

        #expect(segments(log).allSatisfy { !$0.provisional })
    }

    // MARK: - Identity, ordering, clocks

    @Test("duplicate Events change nothing — identity is (viewId, seq), not the timestamp")
    func duplicatesAreDiscarded() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(10_000, pos: 10)
        log.viewEnded(12_000, reason: "nav", pos: 12)

        let once = segments(log)

        // The same batch re-delivered, its copies re-stamped by a later clock.
        // The append-only log keeps both; the first delivery of a `seq` is the
        // one that counts, so the later stamps move nothing.
        var redelivered = log.events
        redelivered += log.events.map { event in
            var copy = event
            copy.t += 60_000
            return copy
        }

        #expect(SegmentComputer.segments(viewId: viewId, events: redelivered) == once)
    }

    @Test("`seq` orders the log, not the order the Events happen to arrive in")
    func seqIsTheOrderingAuthority() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.hidden(7_000, pos: 7)
        log.sample(12_000, playing: true, visible: false, pos: 12)
        log.viewEnded(12_000, reason: "tab-closed", pos: 12)

        #expect(SegmentComputer.segments(viewId: viewId, events: log.events.shuffled()) == segments(log))
    }

    @Test("an Event whose clock stepped backwards is clamped up, never reordered")
    func backwardClockIsClamped() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.sample(-2_000, pos: 10) // the machine's clock jumped back
        log.viewEnded(8_000, reason: "nav", pos: 13)

        let computed = segments(log)
        #expect(computed.count == 1)
        // Clamped to its predecessor: the backward sample adds no time and takes
        // none away.
        #expect(computed[0].wallStartMs == log.at(0))
        #expect(computed[0].wallEndMs == log.at(8_000))
        #expect(computed.allSatisfy { $0.durationMs >= 0 })
    }

    @Test("events that never open or close a Segment leave one span")
    func nonBoundaryEventsAreInert() {
        var log = EventLogBuilder()
        log.mediaFound(0)
        log.metadataChange(500)
        log.play(1_000, pos: 0)
        log.ratechange(3_000, rate: 1.5, pos: 2)
        log.metadataChange(4_000, pos: 3)
        log.unknown("someFutureEvent", 5_000)
        log.sample(6_000, pos: 6)
        log.viewEnded(11_000, reason: "nav", pos: 11)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].durationMs == 10_000)
    }

    @Test("a natural end stops the clock")
    func endedClosesTheSegment() {
        var log = EventLogBuilder()
        log.play(0, pos: 0)
        log.sample(5_000, pos: 5)
        log.ended(10_000, pos: 10)
        // The tab sat on the ended video for another minute.
        log.sample(70_000, playing: false, pos: 10)

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].durationMs == 10_000)
    }

    @Test("a live stream with no reported position still accrues wall-clock time")
    func liveStreamHasNullPositions() {
        var log = EventLogBuilder()
        log.play(0)
        log.sample(5_000)
        log.sample(10_000)
        log.viewEnded(10_000, reason: "nav")

        let computed = segments(log)
        #expect(computed.count == 1)
        #expect(computed[0].durationMs == 10_000)
        #expect(computed[0].posStart == nil)
        #expect(computed[0].posEnd == nil)
    }
}
