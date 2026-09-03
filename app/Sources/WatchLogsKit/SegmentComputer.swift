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
    /// 5 s). A stretch inside a Segment longer than this with **no** heartbeat
    /// and **no** media advance is not playback — it is the Mac asleep or the
    /// network dead — and only the media advance (plus `stallGraceMs`) is
    /// banked for it. The real fix is the Extension noticing the missed beats;
    /// this is the read-side backstop for logs already on disk.
    static let maxHeartbeatGapMs = 180_000
    /// Buffering slack credited to an unmonitored gap on top of its media advance.
    static let stallGraceMs = 60_000

    public static func segments(viewId: String, events: [RawEvent], isLive: Bool = false) -> [Segment] {
        let normalized = normalize(events)
        let hasHeartbeat = normalized.contains { $0.type == .sample }
        var machine = Machine(viewId: viewId, isLive: isLive, hasHeartbeat: hasHeartbeat)
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
    /// Whether this View's log carries any `sample` Events at all. Without them
    /// there is no heartbeat cadence to measure a gap against, so the stall
    /// backstop stays out of the way (`hardCap` / rollup tests drive exactly
    /// this shape).
    let hasHeartbeat: Bool

    /// The last Event's instant and media position, for spotting an
    /// unmonitored gap while a Segment is open.
    private var lastSeenAt: Int?
    private var lastSeenPos: Double?
    /// The latest wall-clock instant the currently open Segment is allowed to
    /// reach: if it spanned a long, heartbeat-free, motionless gap, it may run
    /// only to where that gap's believable playback (media advance +
    /// `stallGraceMs`) would have ended. `.max` means no such gap. Reset by
    /// `close`, so the next Segment starts uncapped.
    private var stallCeilingMs = Int.max

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

    init(viewId: String, isLive: Bool, hasHeartbeat: Bool) {
        self.viewId = viewId
        self.isLive = isLive
        self.hasHeartbeat = hasHeartbeat
    }

    private var foreground: Bool { visible || pip }
    private var kindNow: Segment.Kind { foreground ? .watched : .background }

    mutating func apply(_ event: RawEvent) {
        accountForUnmonitoredGap(before: event)
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

    /// An open Segment that spans a long gap with no heartbeat and no media
    /// progress was not being watched across it — the player was frozen. Bank
    /// only the media advance plus a buffering margin; the rest is subtracted
    /// from the Segment's end in `close`. A `sample`, however sparse, is proof
    /// the player reported in, so a gap a sample ends is left untouched.
    private mutating func accountForUnmonitoredGap(before event: RawEvent) {
        guard hasHeartbeat, !isLive, open != nil, event.type != .sample,
              let lastSeenAt, let lastSeenPos, let pos = event.pos else { return }
        let gap = event.t - lastSeenAt
        guard gap > SegmentComputer.maxHeartbeatGapMs else { return }
        let mediaAdvanceMs = Int(max(0, pos - lastSeenPos) * 1000)
        let credited = min(gap, mediaAdvanceMs + SegmentComputer.stallGraceMs)
        stallCeilingMs = min(stallCeilingMs, lastSeenAt + credited)
    }

    private mutating func start(at t: Int, pos: Double?) {
        open = OpenSegment(kind: kindNow, startMs: t, posStart: pos)
    }

    private mutating func close(at t: Int, pos: Double?, provisional: Bool = false) {
        guard let current = open else { return }
        open = nil
        let ceiling = stallCeilingMs
        stallCeilingMs = Int.max
        // An inferred boundary can predate the Segment it closes (a seek, then
        // a heartbeat revealing a stop with nothing confirmed since). That
        // Segment is zero-length and the noise floor drops it. `ceiling` claws
        // back any frozen-player time the Segment ran past — but never pushes
        // its end earlier than an explicit close instant already did.
        let rawEnd = max(current.startMs, t)
        segments.append(Segment(
            viewId: viewId,
            kind: current.kind,
            wallStartMs: current.startMs,
            wallEndMs: max(current.startMs, min(rawEnd, ceiling)),
            posStart: current.posStart,
            posEnd: pos,
            provisional: provisional
        ))
    }
}
