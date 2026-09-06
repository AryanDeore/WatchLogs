// `wl replay` — one View, the whole pipeline, in one screen.
//
// A debug tool, not part of the shipped app. It answers the question that no
// single layer can: *this row in History says 17 minutes — where did that come
// from?* It walks the same path the data walked, and puts each stage next to
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
//   swift run wl-replay <view-id> --json     # what the db-viewer's Replay tab reads
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

let wantsJSON = options["json"] != nil

if options["help"] != nil || options["h"] != nil {
    print("""
    Replays one View through the pipeline that produced it.

      wl-replay <view-id>          the full report for one View
      wl-replay --find=<text>      Views whose id, video id, title or author match
      wl-replay --recent           the most recent Views
      wl-replay --limit=<n>        how many to list (default 15)
      wl-replay --db=<path>        a database other than the app's own
      wl-replay --json             machine-readable; what the db-viewer reads
      wl-replay --live             read the live database instead of a snapshot

    By default the database is copied to a temporary file first, so the report
    is a stable picture and this can never touch your data while the app runs.
    """)
    exit(0)
}

let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

func emit<T: Encodable>(_ value: T) {
    print(String(decoding: (try? encoder.encode(value)) ?? Data("{}".utf8), as: UTF8.self))
}

/// One way out for both renderings. A caller parsing JSON gets JSON when things
/// go wrong too, or its error handling has to parse prose.
func fail(_ message: String) -> Never {
    if wantsJSON { emit(["error": message]) } else { print(message) }
    exit(1)
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

// MARK: - Listing

let limit = Int(options["limit"] ?? "15") ?? 15

@MainActor
func list(_ records: [ViewRecord]) {
    if wantsJSON {
        emit(["views": records.map(ReplayBuilder.summary)])
        return
    }
    guard !records.isEmpty else {
        print("No Views match. Try --recent, or a shorter --find.")
        return
    }
    for record in records {
        let id = String(record.viewId.prefix(8))
        let title = record.title ?? record.videoId
        print(
            "\(id)  \(Terminal.time(record.startedAtMs))  "
            + "\(Terminal.dim)tab \(record.tabId)\(Terminal.off)  \(title.prefix(52))"
        )
    }
    print("\n\(Terminal.dim)wl-replay <view-id> for the full report\(Terminal.off)")
}

if options["recent"] != nil {
    list(try store.viewRecords(limit: limit))
    exit(0)
}

if let query = options["find"] {
    list(try store.viewRecords(matching: query, limit: limit))
    exit(0)
}

guard let requested = positional.first else {
    fail("Which View? Pass a view id, or --find=<text>, or --recent. --help for more.")
}

// A prefix is enough: nobody types a whole UUID.
let matches = try store.viewRecords(matching: requested, limit: 50)
guard let view = matches.first(where: { $0.viewId == requested })
    ?? (matches.count == 1 ? matches.first : nil) else {
    if matches.isEmpty { fail("No View matches \(requested).") }
    if wantsJSON { fail("\(matches.count) Views match \(requested).") }
    print("\(matches.count) Views match \(requested):\n")
    list(matches)
    exit(1)
}

// MARK: - Gathering

let events = try store.rawEvents(viewId: view.viewId)
let stored = try store.segments(viewId: view.viewId)
let recomputed = SegmentComputer.segments(
    viewId: view.viewId,
    events: events,
    isLive: view.contentFormat == "live"
)

/// The History row this View ended up in, and every View folded into it.
///
/// Resolved through the shipped read model over the Day the View started in —
/// not by grouping Views here. Which Views land in one row is exactly the
/// question this section exists to answer, so asking anything but the real
/// implementation would be answering it twice.
@MainActor
func resolveHistory() throws -> (day: HistoryDay, row: HistoryVideo, members: [ViewRecord])? {
    // `.custom` wants a Day's own label, not an arbitrary instant inside it —
    // the read model clips its calendar-date arithmetic to the currently open
    // Day's label, so a raw timestamp taken from after local midnight but
    // before the Day has confirmed its (activity-flexed, ADR 0001) boundary
    // computes a "day" later than the one that's actually still open, and gets
    // clipped to nothing. Resolving to the Day's own start first — the open
    // Day if the View is still inside it, otherwise whichever frozen Day's
    // window contains it — is what every other caller of `.custom` already
    // does; a View watched at 12:41 AM is exactly the case that goes missing
    // without it.
    let startedAtMs = view.startedAtMs
    let dayStart: Date
    if let openStart = try store.openDayStart(), startedAtMs >= Int(openStart.timeIntervalSince1970 * 1000) {
        dayStart = openStart
    } else if let frozen = try store.frozenDays().first(where: { startedAtMs >= $0.dayStartMs && startedAtMs < $0.dayEndMs }) {
        dayStart = Date(timeIntervalSince1970: Double(frozen.dayStartMs) / 1000)
    } else {
        dayStart = Date(timeIntervalSince1970: Double(startedAtMs) / 1000)
    }
    let days = try store.history(for: .custom(from: dayStart, through: dayStart), now: Date())
    guard
        let day = days.first(where: { $0.videos.contains { $0.viewIds.contains(view.viewId) } }),
        let row = day.videos.first(where: { $0.viewIds.contains(view.viewId) })
    else { return nil }

    let members = try row.viewIds.compactMap { try store.viewRecords(matching: $0, limit: 1).first }
    return (day, row, members)
}

let report = ReplayBuilder.build(
    view: view,
    events: events,
    stored: stored,
    recomputed: recomputed,
    history: try resolveHistory(),
    source: sourcePath,
    snapshot: isSnapshot
)

if wantsJSON {
    emit(report)
} else {
    Terminal.render(report)
}
