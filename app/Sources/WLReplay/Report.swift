import Foundation
import WatchLogsKit

/// One View's journey through the pipeline, as data.
///
/// Built once and rendered twice — as a terminal report and as JSON for the
/// db-viewer — so the two can never tell different stories about the same View.
/// Every judgement (what counts as a suspicious gap, which fold member is a
/// different video) is made here rather than in a renderer, for the same reason.
///
/// These are deliberately flat DTOs rather than the domain types. The JSON is a
/// wire format between two tools and wants to stay still; `RawEvent` and
/// `Segment` answer to the app and should be free to move.
struct ReplayReport: Codable {
    var source: String
    var snapshot: Bool
    var view: ViewHeader
    var events: [EventStep]
    var storedSegments: [SegmentRow]
    var recomputedSegments: [SegmentRow]
    /// True when this build derives something different from the same Events —
    /// which means the stored Segments were written by an older build, not that
    /// either is wrong.
    var recomputeDiffers: Bool
    var storedWatchedMs: Int
    var recomputedWatchedMs: Int
    var history: HistoryRow?

    struct ViewHeader: Codable {
        var viewId: String
        var title: String?
        var author: String?
        var service: String
        var contentFormat: String
        var embedded: Bool
        var videoId: String
        var url: String
        var durationSec: Double?
        var metadataSource: String?
        var adapterId: String?
        var tabId: Int
        var startedAtMs: Int
        var open: Bool
        var previousViewId: String?
        /// The View opened on a page that named no video, so its identity is a
        /// hash of the page address rather than a video id.
        var identityIsHash: Bool
    }

    struct EventStep: Codable {
        var seq: Int
        var type: String
        var tMs: Int
        var pos: Double?
        /// Real time since the previous Event. `nil` on the first.
        var deltaWallMs: Int?
        /// How far the video moved over that same stretch. `nil` when either
        /// end reported no position.
        var deltaMediaMs: Int?
        /// The Event's own payload, already worded: `playing=1 visible=0`, a
        /// seek's `from → to`, a `viewEnded` reason.
        var detail: String?
        /// Set where wall clock and media came apart. The whole reason the two
        /// deltas sit next to each other.
        var warning: String?
    }

    struct SegmentRow: Codable, Equatable {
        var kind: String
        var wallStartMs: Int
        var wallEndMs: Int
        var durationMs: Int
        var posStart: Double?
        var posEnd: Double?
        /// How much of the video this Segment covers, against the wall clock it
        /// claims. Far apart means time was banked that nobody watched.
        var mediaMs: Int?
        var provisional: Bool
        /// Set where this Segment banked Watched time the player never moved
        /// through. The Event log shows the gap; this shows what it became.
        var warning: String?
    }

    struct HistoryRow: Codable {
        var dayLabel: String
        var title: String?
        var watchedMs: Int
        var coverage: Double?
        var knownDurationSec: Double?
        var contentFormat: String
        var embedded: Bool
        var isOpen: Bool
        var isPlaying: Bool
        /// What the row says where a coverage bar cannot be drawn — the exact
        /// string `HistoryPane` falls back to.
        var statusLabel: String
        var fold: [FoldMember]

        struct FoldMember: Codable {
            var viewId: String
            var title: String?
            var videoId: String
            var durationSec: Double?
            /// The View this report is about.
            var isSubject: Bool
            /// False when the fold pulled in a View of a *different* video —
            /// how a row ends up measured against the wrong length.
            var sameVideo: Bool
        }
    }
}

/// A View in a search result: enough to recognise it and ask for the full report.
struct ViewSummary: Codable {
    var viewId: String
    var title: String?
    var author: String?
    var videoId: String
    var tabId: Int
    var startedAtMs: Int
    var open: Bool
}

// MARK: - Building

enum ReplayBuilder {
    /// A gap this long with the video barely moving is the shape phantom
    /// Watched time is made of. A minute is well past any buffering stall and
    /// well short of the App's own three-minute backstop, so this flags the
    /// cases the backstop lets through as well as the ones it catches.
    static let suspiciousGapMs = 60_000

    static func build(
        view: ViewRecord,
        events: [RawEvent],
        stored: [Segment],
        recomputed: [Segment],
        history: (day: HistoryDay, row: HistoryVideo, members: [ViewRecord])?,
        source: String,
        snapshot: Bool
    ) -> ReplayReport {
        ReplayReport(
            source: source,
            snapshot: snapshot,
            view: header(view),
            events: steps(events),
            storedSegments: stored.map(row(_:)),
            recomputedSegments: recomputed.map(row(_:)),
            recomputeDiffers: stored.map(row(_:)) != recomputed.map(row(_:)),
            storedWatchedMs: watched(stored),
            recomputedWatchedMs: watched(recomputed),
            history: history.map { historyRow($0.day, $0.row, $0.members, subject: view) }
        )
    }

    static func summary(_ record: ViewRecord) -> ViewSummary {
        ViewSummary(
            viewId: record.viewId,
            title: record.title,
            author: record.author,
            videoId: record.videoId,
            tabId: record.tabId,
            startedAtMs: record.startedAtMs,
            open: record.open
        )
    }

    private static func watched(_ segments: [Segment]) -> Int {
        segments.filter { $0.kind == .watched }.reduce(0) { $0 + $1.durationMs }
    }

    private static func header(_ view: ViewRecord) -> ReplayReport.ViewHeader {
        ReplayReport.ViewHeader(
            viewId: view.viewId,
            title: view.title,
            author: view.author,
            service: view.service,
            contentFormat: view.contentFormat,
            embedded: view.embedded,
            videoId: view.videoId,
            url: view.url,
            durationSec: view.durationSec,
            metadataSource: view.metadataSource,
            adapterId: view.adapterId,
            tabId: view.tabId,
            startedAtMs: view.startedAtMs,
            open: view.open,
            previousViewId: view.previousViewId,
            identityIsHash: view.videoId.hasPrefix("sha1:")
        )
    }

    private static func steps(_ events: [RawEvent]) -> [ReplayReport.EventStep] {
        var steps: [ReplayReport.EventStep] = []
        var previous: RawEvent?

        for event in events {
            let wallMs = previous.map { event.t - $0.t }
            let mediaMs = previous.flatMap { last -> Int? in
                guard let from = last.pos, let to = event.pos else { return nil }
                return Int((to - from) * 1000)
            }

            var warning: String?
            if let wallMs, wallMs > suspiciousGapMs {
                if let mediaMs, mediaMs < wallMs / 2 {
                    warning = "\(text(wallMs)) of wall clock, \(text(max(0, mediaMs))) of video"
                } else if mediaMs == nil {
                    warning = "\(text(wallMs)) with nothing recorded"
                }
            }

            steps.append(ReplayReport.EventStep(
                seq: event.seq,
                type: name(event.type),
                tMs: event.t,
                pos: event.pos,
                deltaWallMs: wallMs,
                deltaMediaMs: mediaMs,
                detail: detail(event),
                warning: warning
            ))
            previous = event
        }
        return steps
    }

    private static func detail(_ event: RawEvent) -> String? {
        if let from = event.from, let to = event.to {
            return String(format: "%.1f → %.1f", from, to)
        }
        if let reason = event.reason { return reason }
        if let playing = event.playing, let visible = event.visible {
            return "playing=\(playing ? 1 : 0) visible=\(visible ? 1 : 0)"
        }
        return nil
    }

    private static func row(_ segment: Segment) -> ReplayReport.SegmentRow {
        let mediaMs = segment.posStart.flatMap { start in
            segment.posEnd.map { Int(($0 - start) * 1000) }
        }
        // The same rule `wl lint`'s phantom-wall-time check uses, so a Segment
        // flagged in one tool is flagged in the other. Two minutes and half the
        // wall clock: under either, ordinary buffering drowns the signal.
        var warning: String?
        if segment.kind == .watched, segment.durationMs > 120_000,
           let mediaMs, mediaMs < segment.durationMs / 2 {
            warning = "\(text(segment.durationMs)) of Watched time, \(text(max(0, mediaMs))) of video"
        }

        return ReplayReport.SegmentRow(
            kind: segment.kind.rawValue,
            wallStartMs: segment.wallStartMs,
            wallEndMs: segment.wallEndMs,
            durationMs: segment.durationMs,
            posStart: segment.posStart,
            posEnd: segment.posEnd,
            mediaMs: mediaMs,
            provisional: segment.provisional,
            warning: warning
        )
    }

    private static func historyRow(
        _ day: HistoryDay,
        _ row: HistoryVideo,
        _ members: [ViewRecord],
        subject: ViewRecord
    ) -> ReplayReport.HistoryRow {
        // The exact wording `HistoryPane` falls back to when there is no
        // coverage bar to draw. Repeated here rather than approximated: the
        // point of this section is to say what is on screen.
        let status = row.isPlaying ? "Playing now" : row.isOpen ? "Still active" : "No fixed length"

        return ReplayReport.HistoryRow(
            dayLabel: day.label,
            title: row.title,
            watchedMs: row.watchedMs,
            coverage: row.coverage,
            knownDurationSec: row.knownDurationSec,
            contentFormat: row.contentFormat,
            embedded: row.embedded,
            isOpen: row.isOpen,
            isPlaying: row.isPlaying,
            statusLabel: status,
            fold: row.viewIds.map { viewId in
                let member = members.first { $0.viewId == viewId }
                return ReplayReport.HistoryRow.FoldMember(
                    viewId: viewId,
                    title: member?.title,
                    videoId: member?.videoId ?? "",
                    durationSec: member?.durationSec,
                    isSubject: viewId == subject.viewId,
                    sameVideo: member?.videoId == subject.videoId
                )
            }
        )
    }

    /// Milliseconds as a human reads them. Shared so the terminal and the web UI
    /// round the same way.
    static func text(_ ms: Int) -> String {
        let seconds = Double(ms) / 1000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%dm%02ds", Int(seconds) / 60, Int(seconds) % 60)
    }

    static func name(_ type: EventType) -> String {
        switch type {
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
        case .other(let raw): return raw
        }
    }
}
