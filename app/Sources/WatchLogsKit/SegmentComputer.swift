import Foundation

/// Turns one View's raw Event log into its Segments — the whole of ADR 0003 in
/// one pure function.
///
/// Pure is the point: the App re-runs this over a View's *entire* log every time
/// new Events land for it, so a retry, an out-of-order batch, or a
/// crash-recovery Flush hours later all converge on the same answer as a single
/// pass would. Nothing here reads a clock or touches storage.
///
/// The state machine tracks three facts — `playing`, `visible`, `pip` — and
/// keeps one Segment open whenever `playing` holds. Foreground (`visible OR
/// pip`) picks the open Segment's `kind`, so losing the foreground does not stop
/// the clock: it closes the `watched` Segment and opens a `background` one at the
/// same instant. `ratechange`, `metadataChange` and `mediaFound` change nothing.
/// (ADR 0003 lists the PiP toggles as never opening or closing a Segment; they
/// still move the `visible OR pip` condition that decides `kind`, which is what
/// keeps "PiP still counts as Watched" true for a hidden tab.)
public enum SegmentComputer {
    /// Segments shorter than this are discarded — after seek-splitting, so a
    /// burst of scrubbing leaves no sliver behind (ADR 0003).
    public static let noiseFloorMs = 1000

    /// A playing player heartbeats every few seconds (`content.js` SAMPLE_MS =
    /// 5 s). A stretch inside a Segment longer than this with **no media
    /// advance** is not playback — it is the Mac asleep or the network dead —
    /// and only the media advance (plus `stallGraceMs`) is banked for it. The
    /// real fix is the Extension noticing the missed beats (it now does, via
    /// `unwatchedGapMs`); this is the read-side backstop, for logs written
    /// before that landed and for gaps no page was alive to notice.
    static let maxHeartbeatGapMs = 180_000
    /// Buffering slack credited to an unmonitored gap on top of its media advance.
    static let stallGraceMs = 60_000

    public static func segments(viewId: String, events: [RawEvent], isLive: Bool = false) -> [Segment] {
        let normalized = normalize(events)
        var machine = Machine(viewId: viewId, isLive: isLive)
        for event in normalized {
            machine.apply(event)
        }
        return machine.finish()
    }

    /// De-duplicate on `seq` keeping the first delivery, order by `seq`, and
    /// clamp each `t` forward to its predecessor's.
    ///
    /// `seq` is the ordering authority and `(viewId, seq)` the identity —
    /// timestamps are the Extension's, and a clock that steps backwards must not
    /// be able to reorder the log or mint a negative-length Segment.
    static func normalize(_ events: [RawEvent]) -> [RawEvent] {
        var seen = Set<Int>()
        var ordered = events
            .filter { seen.insert($0.seq).inserted }
            .enumerated()
            .sorted { ($0.element.seq, $0.offset) < ($1.element.seq, $1.offset) }
            .map(\.element)

        var floor = Int.min
        for index in ordered.indices {
            ordered[index].t = max(ordered[index].t, floor)
            floor = ordered[index].t
        }
        return ordered
    }
}

/// The Segment state machine. Private to the computation: callers see Events in
/// and Segments out.
private struct Machine {
    struct OpenSegment {
        var kind: Segment.Kind
        var startMs: Int
        var posStart: Double?
    }

    let viewId: String
    let isLive: Bool

    /// The last Event's instant and media position, for spotting an
    /// unmonitored gap while a Segment is open.
    private var lastSeenAt: Int?
    private var lastSeenPos: Double?
    /// The latest wall-clock instant the open Segment has actually earned.
    ///
    /// It starts where the Segment does and creeps forward Event by Event: by
    /// the real time elapsed for an ordinary step, and by only the believable
    /// playback (media advance + `stallGraceMs`) for a step that spanned a long,
    /// motionless gap. `close` takes it as a ceiling, which is what claws a
    /// frozen player's time back out of the Segment.
    ///
    /// Earned forward rather than lost backward, so it composes. A Segment can
    /// span several gaps — a laptop opened and shut twice over an afternoon —
    /// and the hour genuinely watched between two naps still has to count, while
    /// a Segment closed at an instant *before* a gap must not be charged for it
    /// at all.
    private var creditedEndMs = 0

    private var playing = false
    /// A View is born from a media element in a tab the user is looking at
    /// unless something says otherwise; a `hidden` Event or a `sample` is the
    /// only thing that ever says otherwise.
    private var visible = true
    private var pip = false

    private var open: OpenSegment?
    private var segments: [Segment] = []

    /// The last instant at which every condition was positively confirmed, and
    /// the media position there. An inferred boundary falls here — never at the
    /// later Event that merely *revealed* the change (conservative
    /// loss-bounding, ADR 0003).
    private var lastConfirmedAt: Int?
    private var lastConfirmedPos: Double?

    private var viewEnded = false

    init(viewId: String, isLive: Bool) {
        self.viewId = viewId
        self.isLive = isLive
    }

    private var foreground: Bool { visible || pip }
    private var kindNow: Segment.Kind { foreground ? .watched : .background }

    mutating func apply(_ event: RawEvent) {
        creditElapsed(before: event)
        defer {
            lastSeenAt = event.t
            if let pos = event.pos { lastSeenPos = pos }
        }
        switch event.type {
        case .play:
            playing = true
            settle(at: event.t, pos: event.pos)

        case .pause, .ended:
            playing = false
            settle(at: event.t, pos: event.pos)

        case .visible:
            visible = true
            settle(at: event.t, pos: event.pos)

        case .hidden:
            visible = false
            settle(at: event.t, pos: event.pos)

        case .pipEnter:
            pip = true
            settle(at: event.t, pos: event.pos)

        case .pipLeave:
            pip = false
            settle(at: event.t, pos: event.pos)

        case .seeked:
            // Close at the pre-seek position and reopen at the post-seek one, at
            // the same instant: each Segment covers one continuous media range,
            // and a re-watched stretch is a second Segment that counts again.
            // A seek while paused is only a position change.
            guard open != nil else { break }
            close(at: event.t, pos: event.from ?? event.pos)
            start(at: event.t, pos: event.to ?? event.pos)

        case .sample:
            applySample(event)

        case .viewEnded:
            if event.reason == RawEvent.crashRecovered {
                // The Extension stamps a crash-recovered end at the last
                // `sample`. Closing at the last confirmed instant honours that
                // without trusting the stamp — the tail is neither extrapolated
                // nor discarded.
                close(at: lastConfirmedAt ?? event.t, pos: lastConfirmedPos)
            } else {
                close(at: event.t, pos: event.pos)
            }
            playing = false
            viewEnded = true

        case .mediaFound, .ratechange, .metadataChange, .other:
            break
        }
    }

    mutating func finish() -> [Segment] {
        if !viewEnded, let current = open {
            // The View is still running. Its tail cannot be counted past the last
            // positive confirmation, and it is replaced wholesale the next time
            // Events land for this View.
            close(at: lastConfirmedAt ?? current.startMs, pos: lastConfirmedPos, provisional: true)
        }
        return segments.filter { $0.durationMs >= SegmentComputer.noiseFloorMs }
    }

    // MARK: - Transitions

    /// Reconcile the open Segment with the state we now believe, at an instant an
    /// explicit Event vouches for exactly.
    private mutating func settle(at t: Int, pos: Double?) {
        let wanted: Segment.Kind? = playing ? kindNow : nil
        if let current = open, wanted != current.kind {
            close(at: t, pos: pos)
        }
        if wanted != nil, open == nil {
            start(at: t, pos: pos)
        }
    }

    private mutating func applySample(_ event: RawEvent) {
        let samplePlaying = event.playing ?? playing
        let sampleVisible = event.visible ?? visible

        guard samplePlaying != playing || sampleVisible != visible else {
            confirm(event)
            return
        }

        // The heartbeat reveals a change whose Event never arrived: a missed
        // `pause`, a missed `hidden`. It happened somewhere inside
        // (lastConfirmedAt, t]. Close at the near edge and reopen at the far
        // edge, so the uncertain gap counts for nobody.
        close(at: lastConfirmedAt ?? open?.startMs ?? event.t, pos: lastConfirmedPos)
        playing = samplePlaying
        visible = sampleVisible
        if playing {
            start(at: event.t, pos: event.pos)
        }
        confirm(event)
    }

    private mutating func confirm(_ event: RawEvent) {
        lastConfirmedAt = event.t
        lastConfirmedPos = event.pos
    }

    /// Move the open Segment's credit up to this Event, by the real time since
    /// the last one — or by less, where that stretch was not playback.
    ///
    /// An open Segment that spans a long gap with no media progress was not
    /// being watched across it: the player was frozen, or the Mac was asleep, or
    /// the tab was thrown away and never got to heartbeat at all. Such a stretch
    /// earns only the media advance plus a buffering margin, and `close` takes
    /// the difference back off the Segment's end. This applies even to a View
    /// whose log has *no* `sample` Events anywhere — a `play` with nothing else
    /// until an hours-later `viewEnded` is exactly the shape a suspended tab
    /// leaves behind, and it gets no more benefit of the doubt than a gap
    /// between two heartbeats does.
    ///
    /// A `sample` closing the gap is no exemption either, and that is the whole
    /// point: the Extension's timer does not run while the Mac sleeps, so the
    /// first thing after a four-hour lid close is the resumed beat, reporting
    /// `playing` at the position it left off. Trusting it because it is a
    /// heartbeat banked the entire nap. What earns a gap its full credit is the
    /// media having moved across it, whatever Event type happens to reveal that.
    private mutating func creditElapsed(before event: RawEvent) {
        guard open != nil, let lastSeenAt else { return }
        let elapsed = max(0, event.t - lastSeenAt)
        creditedEndMs += min(elapsed, believable(elapsed, at: event))
    }

    /// How much of `elapsed` is playback anyone can vouch for. All of it, unless
    /// this is a long gap whose two ends both carry a media position and those
    /// positions say the player barely moved.
    private func believable(_ elapsed: Int, at event: RawEvent) -> Int {
        guard !isLive, elapsed > SegmentComputer.maxHeartbeatGapMs,
              let lastSeenPos, let pos = event.pos else { return elapsed }
        let mediaAdvanceMs = Int(max(0, pos - lastSeenPos) * 1000)
        return mediaAdvanceMs + SegmentComputer.stallGraceMs
    }

    private mutating func start(at t: Int, pos: Double?) {
        open = OpenSegment(kind: kindNow, startMs: t, posStart: pos)
        creditedEndMs = t
    }

    private mutating func close(at t: Int, pos: Double?, provisional: Bool = false) {
        guard let current = open else { return }
        open = nil
        // An inferred boundary can predate the Segment it closes (a seek, then
        // a heartbeat revealing a stop with nothing confirmed since). That
        // Segment is zero-length and the noise floor drops it. `creditedEndMs`
        // claws back any frozen-player time the Segment ran through — but never
        // pushes its end earlier than an explicit close instant already did.
        let rawEnd = max(current.startMs, t)
        segments.append(Segment(
            viewId: viewId,
            kind: current.kind,
            wallStartMs: current.startMs,
            wallEndMs: max(current.startMs, min(rawEnd, creditedEndMs)),
            posStart: current.posStart,
            posEnd: pos,
            provisional: provisional
        ))
    }
}
