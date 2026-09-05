import Foundation

/// The terminal rendering of a `ReplayReport`.
///
/// Presentation only: every judgement about the data — which gaps are
/// suspicious, which fold member is a different video — was already made in
/// `ReplayBuilder`, so this and the db-viewer's Replay tab cannot disagree
/// about what they are looking at.
@MainActor
enum Terminal {
    static let dim = "\u{1B}[90m", bold = "\u{1B}[1m"
    static let warn = "\u{1B}[33m", bad = "\u{1B}[31m", off = "\u{1B}[0m"

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss a"
        return formatter
    }()

    static func time(_ ms: Int) -> String {
        clock.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    static func seconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    /// Right-aligned in `width` columns.
    ///
    /// Not a C-string format: on Darwin those want an actual C string, and
    /// handing one a Swift or Foundation string sends it walking memory that is
    /// not a string until it finds a zero byte — which reads as the tool
    /// hanging rather than as the mistake it is.
    static func padLeft(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    private static func heading(_ text: String, _ trailing: String = "") {
        print("\n\(bold)\(text)\(off)  \(dim)\(trailing)\(off)")
    }

    static func render(_ report: ReplayReport) {
        print("\(dim)\(report.source)\(report.snapshot ? " (snapshot)" : " (live)")\(off)")
        renderView(report.view)
        renderEvents(report.events)
        renderSegments(report)
        renderHistory(report.history)
        print("")
    }

    private static func renderView(_ view: ReplayReport.ViewHeader) {
        heading("VIEW", view.viewId)
        print("  \(bold)\(view.title ?? "Untitled")\(off)")
        var line = [view.author, view.service, view.contentFormat].compactMap { $0 }
        if view.embedded { line.append("embedded") }
        print("  \(line.joined(separator: " · "))")
        print("  tab \(view.tabId) · started \(time(view.startedAtMs)) · \(view.open ? "\(warn)open\(off)" : "closed")")
        print(
            "  \(dim)video \(view.videoId) · duration \(view.durationSec.map { String(format: "%.1fs", $0) } ?? "—")"
            + " · metadata \(view.metadataSource ?? "—")/\(view.adapterId ?? "no adapter")\(off)"
        )
        if view.identityIsHash {
            print("  \(warn)identity is a page-address hash — the page named no video when this View opened\(off)")
        }
    }

    private static func renderEvents(_ events: [ReplayReport.EventStep]) {
        heading("EVENTS", "\(events.count) recorded")
        print("  \(dim)seq  time                 Δwall    Δmedia  type            pos\(off)")
        for event in events {
            let note = event.warning.map { " \(bad)⚠ \($0)\(off)" } ?? ""
            let detail = event.detail.map { "\(dim)\($0)\(off)" } ?? ""
            print(
                "  \(padLeft(String(event.seq), 3))  \(time(event.tMs))  "
                + "\(padLeft(event.deltaWallMs.map { ReplayBuilder.text($0) } ?? "—", 7))  "
                + "\(padLeft(event.deltaMediaMs.map { ReplayBuilder.text(max(0, $0)) } ?? "—", 7))  "
                + "\(event.type.padding(toLength: 14, withPad: " ", startingAt: 0))  "
                + "\(padLeft(seconds(event.pos), 8))  \(detail)\(note)"
            )
        }
    }

    private static func renderSegments(_ report: ReplayReport) {
        heading(
            "SEGMENTS",
            "\(report.storedSegments.count) stored · \(report.recomputedSegments.count) recomputed by this build"
        )
        show(report.storedSegments)

        // Disagreement here is not necessarily a bug in the data: Segments are
        // computed at Flush time, so a View recorded before a fix landed keeps
        // the answer the old build gave. Saying which of the two you are looking
        // at is the point.
        guard report.recomputeDiffers else { return }
        print("\n  \(warn)this build would derive something different from the same Events:\(off)")
        show(report.recomputedSegments)
        print(
            "  \(warn)Watched: \(ReplayBuilder.text(report.storedWatchedMs)) stored → "
            + "\(ReplayBuilder.text(report.recomputedWatchedMs)) recomputed"
            + " — the stored Segments were written by an older build\(off)"
        )
    }

    private static func show(_ segments: [ReplayReport.SegmentRow]) {
        if segments.isEmpty {
            print("  \(dim)none\(off)")
            return
        }
        for segment in segments {
            let kind = segment.kind == "watched" ? "watched   " : "background"
            let media = segment.mediaMs.map { " \(dim)media \(ReplayBuilder.text(max(0, $0)))\(off)" } ?? ""
            print(
                "  \(kind)  \(time(segment.wallStartMs)) → \(time(segment.wallEndMs))  "
                + "\(padLeft(ReplayBuilder.text(segment.durationMs), 8))  "
                + "\(dim)pos \(seconds(segment.posStart)) → \(seconds(segment.posEnd))\(off)"
                + "\(media)\(segment.provisional ? " \(dim)(provisional)\(off)" : "")"
                + (segment.warning.map { " \(bad)⚠ \($0)\(off)" } ?? "")
            )
        }
    }

    private static func renderHistory(_ history: ReplayReport.HistoryRow?) {
        heading("HISTORY", "what the popover renders for this View")
        guard let history else {
            print("  \(dim)no History row — this View contributed no Watched time to its Day\(off)")
            return
        }

        var badges: [String] = []
        if history.contentFormat == "live" { badges.append("live") }
        if history.embedded { badges.append("embedded") }
        let progress = history.coverage.map { String(format: "bar %.0f%%", $0 * 100) } ?? history.statusLabel

        print("  \(bold)\(history.title ?? "Untitled")\(off)")
        print(
            "  \(ReplayBuilder.text(history.watchedMs)) · \(progress)"
            + (badges.isEmpty ? "" : " · \(badges.joined(separator: " · "))")
            + " · \(dim)day \(history.dayLabel)\(off)"
        )

        // The fold is where a correct View becomes a wrong row. More than one
        // View is ordinary — a re-watch — but a fold that pulled in a View of a
        // *different* video is how a row ends up measured against the wrong
        // length.
        guard history.fold.count > 1 else { return }
        print("\n  folded from \(history.fold.count) Views:")
        for member in history.fold {
            let marker = member.isSubject ? "→" : " "
            let length = (member.durationSec.map { String(format: "%.1fs", $0) } ?? "—")
                .padding(toLength: 9, withPad: " ", startingAt: 0)
            print(
                "  \(marker) \(String(member.viewId.prefix(8)))  \(length)"
                + "  \((member.title ?? member.videoId).prefix(44))"
                + (member.sameVideo ? "" : " \(bad)← a different video\(off)")
            )
        }
        if let longest = history.knownDurationSec {
            print(
                "  \(dim)the bar is measured against \(String(format: "%.1fs", longest))"
                + " — the longest duration in the fold\(off)"
            )
        }
    }
}
