import Foundation

/// One recorded fact about playback, exactly as the Extension sent it (schema
/// v1, `prototypes/message-schema/SCHEMA.md`).
///
/// Stable identity is `(viewId, seq)` — never `t` (ADR 0003). The App stores
/// these verbatim and never rewrites their timestamps; the monotonicity clamp
/// lives in `SegmentComputer`, on the way out of the log rather than into it.
public struct RawEvent: Equatable, Sendable {
    public var seq: Int
    public var type: EventType
    /// Extension wall clock at capture, epoch ms.
    public var t: Int
    /// Media position in seconds. Null before play and on a live stream with no
    /// DVR window.
    public var pos: Double?

    // Type-specific fields. Each is nil for every type that does not carry it.
    /// `seeked`: the pre-seek position.
    public var from: Double?
    /// `seeked`: the post-seek position.
    public var to: Double?
    /// `ratechange`: the new playback speed. Never affects Watched time —
    /// Watched time is wall-clock (ADR 0003).
    public var rate: Double?
    /// `sample`: the heartbeat's view of the two conditions.
    public var playing: Bool?
    public var visible: Bool?
    /// `viewEnded`: `nav` | `tab-closed` | `video-changed` | `crash-recovered`,
    /// or an unrecognised reason recorded uninterpreted.
    public var reason: String?

    public init(
        seq: Int,
        type: EventType,
        t: Int,
        pos: Double? = nil,
        from: Double? = nil,
        to: Double? = nil,
        rate: Double? = nil,
        playing: Bool? = nil,
        visible: Bool? = nil,
        reason: String? = nil
    ) {
        self.seq = seq
        self.type = type
        self.t = t
        self.pos = pos
        self.from = from
        self.to = to
        self.rate = rate
        self.playing = playing
        self.visible = visible
        self.reason = reason
    }

    /// The `viewEnded` reason that means the browser died mid-View: `t` and
    /// `pos` are the last `sample`, not "now".
    public static let crashRecovered = "crash-recovered"
}

/// The Event `type`. An unrecognised type is kept as `.other` rather than
/// rejected: adding an event type is an additive schema change, and an older App
/// must record it uninterpreted (SCHEMA, "Schema versioning").
public enum EventType: Equatable, Sendable {
    case mediaFound
    case play
    case pause
    case seeked
    case ratechange
    case visible
    case hidden
    case pipEnter
    case pipLeave
    case metadataChange
    case sample
    case ended
    case viewEnded
    case other(String)

    public init(name: String) {
        switch name {
        case "mediaFound": self = .mediaFound
        case "play": self = .play
        case "pause": self = .pause
        case "seeked": self = .seeked
        case "ratechange": self = .ratechange
        case "visible": self = .visible
        case "hidden": self = .hidden
        case "pipEnter": self = .pipEnter
        case "pipLeave": self = .pipLeave
        case "metadataChange": self = .metadataChange
        case "sample": self = .sample
        case "ended": self = .ended
        case "viewEnded": self = .viewEnded
        default: self = .other(name)
        }
    }

    public var name: String {
        switch self {
        case .mediaFound: return "mediaFound"
        case .play: return "play"
        case .pause: return "pause"
        case .seeked: return "seeked"
        case .ratechange: return "ratechange"
        case .visible: return "visible"
        case .hidden: return "hidden"
        case .pipEnter: return "pipEnter"
        case .pipLeave: return "pipLeave"
        case .metadataChange: return "metadataChange"
        case .sample: return "sample"
        case .ended: return "ended"
        case .viewEnded: return "viewEnded"
        case .other(let name): return name
        }
    }
}
