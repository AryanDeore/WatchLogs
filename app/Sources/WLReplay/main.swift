// `wl replay` — one View, the whole pipeline, in one screen.
//
// A debug tool, not part of the shipped app. It answers the question that no
// single layer can: *this row in History says 17 minutes — where did that come
// from?* It walks the same path the data walked, and prints each stage next to
// the one before it:
//
//     the View header        what the Extension said this video was
//     the Event log          what it observed, with the gaps made visible
//     the Segments           what the App derived, stored and recomputed
//     the History row        what the popover puts on screen
//
// The one rule that makes this worth trusting: it calls the **shipped**
// `SegmentComputer` and the shipped read model. A tool that re-implemented
// either would have its own bugs and could only ever tell you about itself.
//
// Usage:
//   swift run wl-replay <view-id>
//   swift run wl-replay --find="lofi"        # look it up by title, id or author
//   swift run wl-replay --recent             # the last few Views, newest first
//   swift run wl-replay <view-id> --live     # skip the snapshot (see below)

import Foundation
import WatchLogsKit

// MARK: - Arguments

let arguments = CommandLine.arguments.dropFirst()
var options: [String: String] = [:]
var positional: [String] = []
for argument in arguments {
    if argument.hasPrefix("--") {
        let body = argument.dropFirst(2)
        let parts = body.split(separator: "=", maxSplits: 1)
        options[String(parts[0])] = parts.count > 1 ? String(parts[1]) : "true"
    } else {
        positional.append(argument)
    }
}

if options["help"] != nil || options["h"] != nil {
    print("""
    Replays one View through the pipeline that produced it.

      wl-replay <view-id>          the full report for one View
      wl-replay --find=<text>      Views whose id, video id, title or author match
      wl-replay --recent           the most recent Views
      wl-replay --limit=<n>        how many to list (default 15)
      wl-replay --db=<path>        a database other than the app's own
      wl-replay --live             read the live database instead of a snapshot

    By default the database is copied to a temporary file first, so the report
    is a stable picture and this can never touch your data while the app runs.
    """)
    exit(0)
}

// MARK: - Opening the database

/// The database this run reads.
///
/// A snapshot by default, deliberately. `EventStore.init` is a read-write open —
/// it applies the schema and an additive migration — and pointing that at a
/// database a running app owns is not something a debug tool should do by
/// accident. Copying costs a few megabytes and makes the report a stable
/// picture of one instant rather than a moving target: with the app flushing
/// every few seconds, the Segments section could otherwise disagree with the
/// Events section it was computed from.
@MainActor
func openStore() throws -> (store: EventStore, path: String, snapshot: Bool) {
    let source = try options["db"] ?? EventStore.defaultPath()
    guard options["live"] == nil else {
        return (try EventStore(path: source), source, false)
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("wl-replay-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("watchlogs.sqlite").path

    // The write-ahead log holds everything since the last checkpoint — which,
    // with the app running, is most of what you came to look at. Copying the
    // database without it silently reads a stale database.
    for suffix in ["", "-wal", "-shm"] {
        let from = source + suffix
        guard FileManager.default.fileExists(atPath: from) else { continue }
        try FileManager.default.copyItem(atPath: from, toPath: destination + suffix)
    }
    return (try EventStore(path: destination), source, true)
}

let (store, sourcePath, isSnapshot) = try openStore()

// MARK: - Formatting

let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm:ss a"
    return formatter
}()

func time(_ ms: Int) -> String { clock.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }

func duration(_ ms: Int) -> String {
    let seconds = Double(ms) / 1000
    if seconds < 60 { return String(format: "%.1fs", seconds) }
    return String(format: "%dm%02ds", Int(seconds) / 60, Int(seconds) % 60)
}

func seconds(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f", value)
}

/// Right-aligned in `width` columns.
///
/// Not a C-string format: on Darwin those want an actual C string, and handing
/// one a Swift or Foundation string sends it walking memory that is not a
/// string until it finds a zero byte — which reads as the tool hanging.
func padLeft(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

let dim = "\u{1B}[90m", bold = "\u{1B}[1m", warn = "\u{1B}[33m", bad = "\u{1B}[31m", off = "\u{1B}[0m"

func heading(_ text: String, _ trailing: String = "") {
    print("\n\(bold)\(text)\(off)  \(dim)\(trailing)\(off)")
}

// MARK: - Listing

func list(_ records: [ViewRecord]) {
    guard !records.isEmpty else {
        print("No Views match. Try --recent, or a shorter --find.")
        return
    }
    for record in records {
        let id = String(record.viewId.prefix(8))
        let title = record.title ?? record.videoId
        print("\(id)  \(time(record.startedAtMs))  \(dim)tab \(record.tabId)\(off)  \(title.prefix(52))")
    }
    print("\n\(dim)wl-replay <view-id> for the full report\(off)")
}

let limit = Int(options["limit"] ?? "15") ?? 15

if options["recent"] != nil {
    list(try store.viewRecords(limit: limit))
    exit(0)
}

if let query = options["find"] {
    list(try store.viewRecords(matching: query, limit: limit))
    exit(0)
}

guard let requested = positional.first else {
    print("Which View? Pass a view id, or --find=<text>, or --recent. --help for more.")
    exit(1)
}

// A prefix is enough: nobody types a whole UUID.
let matches = try store.viewRecords(matching: requested, limit: 50)
guard let view = matches.first(where: { $0.viewId == requested })
    ?? (matches.count == 1 ? matches.first : nil) else {
    if matches.isEmpty {
        print("No View matches \(requested).")
    } else {
        print("\(matches.count) Views match \(requested):\n")
        list(matches)
    }
    exit(1)
}

// MARK: - The View header

print("\(dim)\(sourcePath)\(isSnapshot ? " (snapshot)" : " (live)")\(off)")

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
if view.videoId.hasPrefix("sha1:") {
    print("  \(warn)identity is a page-address hash — the page named no video when this View opened\(off)")
}

// MARK: - The Event log

let events = try store.rawEvents(viewId: view.viewId)

heading("EVENTS", "\(events.count) recorded")
print("  \(dim)seq  time                 Δwall    Δmedia  type            pos\(off)")

var previous: RawEvent?
for event in events {
    let wallMs = previous.map { event.t - $0.t }
    let mediaMs = previous.flatMap { last -> Int? in
        guard let from = last.pos, let to = event.pos else { return nil }
        return Int((to - from) * 1000)
    }

    // The one comparison this whole tool exists to make legible: how much real
    // time passed against how much of the video went by. They track each other
    // during playback and come apart everywhere playback was assumed rather
    // than observed.
    var note = ""
    if let wallMs, let mediaMs, wallMs > 60_000, mediaMs < wallMs / 2 {
        note = " \(bad)⚠ \(duration(wallMs)) of wall clock, \(duration(max(0, mediaMs))) of video\(off)"
    } else if let wallMs, wallMs > 60_000 {
        note = " \(warn)⚠ \(duration(wallMs)) with nothing recorded\(off)"
    }

    var detail = ""
    if let playing = event.playing, let visible = event.visible {
        detail = "\(dim)playing=\(playing ? 1 : 0) visible=\(visible ? 1 : 0)\(off)"
    }
    if let reason = event.reason { detail = "\(dim)\(reason)\(off)" }
    if let from = event.from, let to = event.to {
        detail = "\(dim)\(seconds(from)) → \(seconds(to))\(off)"
    }

    print(
        "  \(String(format: "%3d", event.seq))  \(time(event.t))  "
        + "\(padLeft(wallMs.map { duration($0) } ?? "—", 7))  "
        + "\(padLeft(mediaMs.map { duration(max(0, $0)) } ?? "—", 7))  "
        + "\(name(event.type).padding(toLength: 14, withPad: " ", startingAt: 0))  "
        + "\(padLeft(seconds(event.pos), 8))  \(detail)\(note)"
    )
    previous = event
}

func name(_ type: EventType) -> String {
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

// MARK: - Segments: what is stored, and what this build would derive

let stored = try store.segments(viewId: view.viewId)
let recomputed = SegmentComputer.segments(
    viewId: view.viewId,
    events: events,
    isLive: view.contentFormat == "live"
)

heading("SEGMENTS", "\(stored.count) stored · \(recomputed.count) recomputed by this build")
func show(_ segments: [Segment], label: String) {
    if segments.isEmpty {
        print("  \(dim)\(label): none\(off)")
        return
    }
    for segment in segments {
        let kind = segment.kind == .watched ? "watched   " : "background"
        let mediaMs = segment.posStart.flatMap { start in
            segment.posEnd.map { Int(($0 - start) * 1000) }
        }
        let ratio = mediaMs.map { " \(dim)media \(duration(max(0, $0)))\(off)" } ?? ""
        print(
            "  \(kind)  \(time(segment.wallStartMs)) → \(time(segment.wallEndMs))  "
            + "\(padLeft(duration(segment.durationMs), 8))  "
            + "\(dim)pos \(seconds(segment.posStart)) → \(seconds(segment.posEnd))\(off)"
            + "\(ratio)\(segment.provisional ? " \(dim)(provisional)\(off)" : "")"
        )
    }
}

show(stored, label: "stored")

// Disagreement here is not necessarily a bug in the data: Segments are computed
// at Flush time, so a View recorded before a fix landed keeps the answer the old
// build gave. Saying which of the two you are looking at is the point.
if stored != recomputed {
    let storedWatched = stored.filter { $0.kind == .watched }.reduce(0) { $0 + $1.durationMs }
    let freshWatched = recomputed.filter { $0.kind == .watched }.reduce(0) { $0 + $1.durationMs }
    print("\n  \(warn)this build would derive something different from the same Events:\(off)")
    show(recomputed, label: "recomputed")
    print(
        "  \(warn)Watched: \(duration(storedWatched)) stored → \(duration(freshWatched)) recomputed"
        + " — the stored Segments were written by an older build\(off)"
    )
}

// MARK: - What the popover puts on screen

let startedAt = Date(timeIntervalSince1970: Double(view.startedAtMs) / 1000)
let day = try store.history(for: .custom(from: startedAt, through: startedAt), now: Date())
    .first { $0.videos.contains { $0.viewIds.contains(view.viewId) } }
let row = day?.videos.first { $0.viewIds.contains(view.viewId) }

heading("HISTORY", "what the popover renders for this View")
if let row, let day {
    var badges: [String] = []
    if row.contentFormat == "live" { badges.append("live") }
    if row.embedded { badges.append("embedded") }
    let progress = row.coverage.map { String(format: "bar %.0f%%", $0 * 100) }
        ?? (row.isPlaying ? "Playing now" : row.isOpen ? "Still watching" : "No fixed length")
    print("  \(bold)\(row.title ?? "Untitled")\(off)")
    print(
        "  \(duration(row.watchedMs)) · \(progress)"
        + (badges.isEmpty ? "" : " · \(badges.joined(separator: " · "))")
        + " · \(dim)day \(day.label)\(off)"
    )

    // The fold is where a correct View becomes a wrong row. `watchCount > 1` is
    // ordinary — a re-watch — but a fold that pulled in a View of a *different*
    // video is how a row ends up measured against the wrong length.
    if row.viewIds.count > 1 {
        print("\n  folded from \(row.viewIds.count) Views:")
        for id in row.viewIds {
            guard let member = try store.viewRecords(matching: id, limit: 1).first else { continue }
            let mine = member.viewId == view.viewId ? "→" : " "
            let sameVideo = member.videoId == view.videoId
            let duration = member.durationSec.map { String(format: "%.1fs", $0) } ?? "—"
            print(
                "  \(mine) \(String(member.viewId.prefix(8)))  \(duration.padding(toLength: 9, withPad: " ", startingAt: 0))"
                + "  \((member.title ?? member.videoId).prefix(44))"
                + (sameVideo ? "" : " \(bad)← a different video\(off)")
            )
        }
        if let longest = row.knownDurationSec {
            print(
                "  \(dim)the bar is measured against \(String(format: "%.1fs", longest))"
                + " — the longest duration in the fold\(off)"
            )
        }
    }
} else {
    print("  \(dim)no History row — this View contributed no Watched time to its Day\(off)")
}

print("")
