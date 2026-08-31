import Foundation

/// One continuous span of wall-clock time during which a View was playing
/// (`CONTEXT.md`, ADR 0003).
///
/// `kind` splits that span by whether the tab was in the foreground: `watched`
/// time is the headline number, `background` is kept but never counts as Watched
/// time. Segments are stored **whole** — never cut at a Day boundary; clipping
/// to a date range happens at read time.
public struct Segment: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// Playing and in the foreground (`visible` or Picture-in-Picture).
        case watched
        /// Playing, but the tab was not in the foreground — Background audio.
        case background
    }

    public var viewId: String
    public var kind: Kind
    public var wallStartMs: Int
    /// Exclusive. A seek produces two Segments with a zero wall-clock gap, so
    /// one Segment's `wallEndMs` is the next one's `wallStartMs`.
    public var wallEndMs: Int
    /// Media position at the two ends, seconds. Null on a live stream with no
    /// reported position.
    public var posStart: Double?
    public var posEnd: Double?
    /// True for the trailing Segment of a View that has not ended: it is
    /// replaced wholesale on the next recompute.
    public var provisional: Bool

    public init(
        viewId: String,
        kind: Kind,
        wallStartMs: Int,
        wallEndMs: Int,
        posStart: Double? = nil,
        posEnd: Double? = nil,
        provisional: Bool = false
    ) {
        self.viewId = viewId
        self.kind = kind
        self.wallStartMs = wallStartMs
        self.wallEndMs = wallEndMs
        self.posStart = posStart
        self.posEnd = posEnd
        self.provisional = provisional
    }

    public var durationMs: Int { wallEndMs - wallStartMs }
}
