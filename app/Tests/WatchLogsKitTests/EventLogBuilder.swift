import Foundation
@testable import WatchLogsKit

/// Builds a View's Event log the way the Extension does: `seq` from 1, in the
/// order the facts happened, with the Extension's own wall clock on each Event.
///
/// Times are relative milliseconds so a test reads as a story ("play at 0, still
/// playing at 5s, hidden at 7s") instead of a wall of epoch numbers.
struct EventLogBuilder {
    /// The wall clock the View starts at. Any epoch instant works — Segment
    /// computation never reads a clock of its own.
    var origin = 1_788_026_400_000

    private(set) var events: [RawEvent] = []
    private var nextSeq = 1

    init(origin: Int = 1_788_026_400_000) {
        self.origin = origin
    }

    mutating func mediaFound(_ ms: Int, pos: Double? = 0) { add(.mediaFound, ms, pos: pos) }
    mutating func play(_ ms: Int, pos: Double? = nil) { add(.play, ms, pos: pos) }
    mutating func pause(_ ms: Int, pos: Double? = nil) { add(.pause, ms, pos: pos) }
    mutating func ended(_ ms: Int, pos: Double? = nil) { add(.ended, ms, pos: pos) }
    mutating func visible(_ ms: Int, pos: Double? = nil) { add(.visible, ms, pos: pos) }
    mutating func hidden(_ ms: Int, pos: Double? = nil) { add(.hidden, ms, pos: pos) }
    mutating func pipEnter(_ ms: Int, pos: Double? = nil) { add(.pipEnter, ms, pos: pos) }
    mutating func pipLeave(_ ms: Int, pos: Double? = nil) { add(.pipLeave, ms, pos: pos) }
    mutating func metadataChange(_ ms: Int, pos: Double? = nil) { add(.metadataChange, ms, pos: pos) }

    mutating func seeked(_ ms: Int, from: Double, to: Double) {
        add(.seeked, ms, pos: to, from: from, to: to)
    }

    mutating func ratechange(_ ms: Int, rate: Double, pos: Double? = nil) {
        add(.ratechange, ms, pos: pos, rate: rate)
    }

    mutating func sample(_ ms: Int, playing: Bool = true, visible: Bool = true, pos: Double? = nil) {
        add(.sample, ms, pos: pos, playing: playing, visible: visible)
    }

    mutating func viewEnded(_ ms: Int, reason: String = "nav", pos: Double? = nil) {
        add(.viewEnded, ms, pos: pos, reason: reason)
    }

    /// An Event type this build of the App has never heard of.
    mutating func unknown(_ name: String, _ ms: Int) { add(.other(name), ms) }

    /// The absolute timestamp `ms` milliseconds into the View.
    func at(_ ms: Int) -> Int { origin + ms }

    private mutating func add(
        _ type: EventType,
        _ ms: Int,
        pos: Double? = nil,
        from: Double? = nil,
        to: Double? = nil,
        rate: Double? = nil,
        playing: Bool? = nil,
        visible: Bool? = nil,
        reason: String? = nil
    ) {
        events.append(RawEvent(
            seq: nextSeq,
            type: type,
            t: origin + ms,
            pos: pos,
            from: from,
            to: to,
            rate: rate,
            playing: playing,
            visible: visible,
            reason: reason
        ))
        nextSeq += 1
    }
}
