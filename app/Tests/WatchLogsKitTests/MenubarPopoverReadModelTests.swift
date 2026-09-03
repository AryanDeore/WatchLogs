import Foundation
import Testing
@testable import WatchLogsKit

/// The menubar popover's public backing model (issue #23): the state holder
/// that preserves the active pane across range changes, and the resolved
/// read-model data the SwiftUI views read from.
///
/// Tests exercise the model against a real `EventStore` (`:memory:` SQLite)
/// so the read-model SQL is the same SQL production runs — no screen
/// automation, no view-layer mocks.
@Suite("Menubar popover read model", .serialized)
struct MenubarPopoverReadModelTests {
    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func envelope(flushId: String = UUID().uuidString, views: [String]) -> Data {
        Data(#"""
        {"schemaVersion":1,"flushId":"\#(flushId)","sentAt":1700000000000,
         "agent":{"extInstanceId":"ext-1","extVersion":"0.1.0","browser":"chrome","os":"macOS"},
         "views":[\#(views.joined(separator: ","))]}
        """#.utf8)
    }

    private func closedViewJSON(
        viewId: String,
        startMs: Int,
        durationMs: Int,
        service: String = "youtube",
        contentFormat: String = "standard",
        adapterId: String? = "youtube"
    ) -> String {
        let adapterField = adapterId.map { #""\#($0)""# } ?? "null"
        return #"""
        {"viewId":"\#(viewId)","service":"\#(service)","contentFormat":"\#(contentFormat)","embedded":false,
         "videoId":"v","url":"https://example.com/v","tabId":1,"startedAt":\#(startMs),
         "adapterId":\#(adapterField),
         "open":false,"previousViewId":null,"events":[
           { "seq": 1, "type": "mediaFound", "t": \#(startMs), "pos": 0 },
           { "seq": 2, "type": "play", "t": \#(startMs), "pos": 0 },
           { "seq": 3, "type": "viewEnded", "t": \#(startMs + durationMs), "pos": 0, "reason": "nav" }
         ]}
        """#
    }

    private func post(_ body: Data, to service: LoopbackTransport, using client: RawHTTPClient) throws {
        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(service.pairing().token)", "Content-Type": "application/json"],
            body: body
        )
        #expect(response.status == 200)
    }

    /// Bring up a service backed by a caller-supplied store so the test can
    /// hand the same store to the read model.
    private func makeService(store: EventStore, clock: Clock) throws -> (service: LoopbackTransport, client: RawHTTPClient) {
        let port = Int.random(in: 49_200..<52_000)
        let service = try LoopbackTransport(
            version: "0.1.0",
            tokenStore: InMemoryTokenStore(),
            store: store,
            clock: clock,
            config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        )
        try service.start()
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
        return (service, client)
    }

    @Test("branded display buckets accept both the Adapter id and the bare hostname")
    func serviceDisplayBucketsAcceptAdapterIdsAndHostnames() {
        // Adapter-id form: shipped Adapters and the dev scripts.
        #expect(ServiceDisplayBucket.from(service: "youtube") == .youtube)
        #expect(ServiceDisplayBucket.from(service: "netflix") == .netflix)

        // Hostname form: the current Adapter-less extension slice.
        #expect(ServiceDisplayBucket.from(service: "youtube.com") == .youtube)
        #expect(ServiceDisplayBucket.from(service: "www.youtube.com") == .youtube)
        #expect(ServiceDisplayBucket.from(service: "m.youtube.com") == .youtube)
        #expect(ServiceDisplayBucket.from(service: "youtu.be") == .youtube)
        #expect(ServiceDisplayBucket.from(service: "netflix.com") == .netflix)

        // Everything else folds into otherSites.
        #expect(ServiceDisplayBucket.from(service: "twitch") == .otherSites)
        #expect(ServiceDisplayBucket.from(service: "thisishulu.com") == .otherSites)
        #expect(ServiceDisplayBucket.from(service: "unknown") == .otherSites)
    }

    @Test("range labels use the readable calendar form even with no watched Views")
    func rangeLabelUsesReadableCalendarForm() throws {
        let store = try EventStore(path: ":memory:")
        let now = local(2024, 8, 29, 12)
        _ = try store.record(flush(sentAt: now.epochMillis), serverTime: now.epochMillis)

        #expect(try store.rangeLabel(for: .today, now: now) == "Aug 29")
    }

    // MARK: - Pane preservation across range changes

    @Test("changing the range preserves the active pane and updates the resolved trends data")
    func changingRangePreservesActivePaneAndUpdatesTrends() throws {
        let clock = ManualClock(local(2024, 1, 29, 12, 0))
        let store = try EventStore(path: ":memory:")
        let (service, client) = try makeService(store: store, clock: clock)
        defer { service.stop() }

        try post(envelope(views: [closedViewJSON(viewId: "mon", startMs: local(2024, 1, 29, 12, 0).epochMillis, durationMs: 60_000)]), to: service, using: client)
        clock.set(local(2024, 1, 30, 4, 0)) // freezes Monday.
        clock.set(local(2024, 2, 1, 12, 0))

        let model = MenubarPopoverReadModel(store: store, clock: clock)
        model.pane = .trends
        model.selectRange(.thisWeek)
        let weekTrends = model.resolved.trends

        model.selectRange(.thisMonth)
        let monthTrends = model.resolved.trends

        #expect(model.pane == .trends)
        #expect(weekTrends.count == 4) // Mon Jan 29 through Thu Feb 1
        #expect(monthTrends.count == 1) // Feb 1
        #expect(weekTrends.first?.label == "2024-01-29")
        #expect(weekTrends.first?.totalMs == 60_000)
        #expect(monthTrends.first?.label == "2024-02-01")
        #expect(monthTrends.first?.totalMs == 0)
    }

    private func flush(sentAt: Int, views: [FlushView] = []) -> FlushEnvelope {
        FlushEnvelope(
            schemaVersion: 1,
            flushId: UUID().uuidString,
            sentAt: sentAt,
            agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"),
            views: views
        )
    }

    private func closedView(id: String, start: Int, durationMs: Int = 60_000) -> FlushView {
        FlushView(
            viewId: id, service: "youtube", videoId: "v", url: "https://example.com/v",
            adapterId: "youtube", tabId: 1, startedAt: start, open: false,
            events: [
                RawEvent(seq: 1, type: .mediaFound, t: start, pos: 0),
                RawEvent(seq: 2, type: .play, t: start, pos: 0),
                RawEvent(seq: 3, type: .viewEnded, t: start + durationMs, pos: Double(durationMs) / 1_000, reason: "nav"),
            ]
        )
    }

    @Test("raw Event retention persists after reopening a file-backed store")
    func rawEventRetentionPersistsAcrossReopen() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlogs-retention-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        do {
            let store = try EventStore(path: path)
            try store.setRawEventRetentionDays(14)
            #expect(try store.rawEventRetentionDays() == 14)
        }

        let reopened = try EventStore(path: path)
        #expect(try reopened.rawEventRetentionDays() == 14)
    }

    @Test("an accepted Flush automatically prunes raw Events from closed Views")
    func acceptedFlushAutomaticallyPrunesClosedViewEvents() throws {
        let store = try EventStore(path: ":memory:")
        let start = local(2024, 1, 1, 12).epochMillis
        _ = try store.record(flush(sentAt: start + 60_000, views: [closedView(id: "closed", start: start)]), serverTime: start + 60_000)
        #expect(try store.counts().rawEvents == 3)

        try store.setRawEventRetentionDays(0)
        _ = try store.record(flush(sentAt: local(2024, 1, 2, 12).epochMillis), serverTime: local(2024, 1, 2, 12).epochMillis)

        #expect(try store.counts().rawEvents == 0)
    }

    @Test("pruning raw Events keeps Segments and frozen-Day rollup reads intact")
    func pruningKeepsSegmentsAndFrozenDayRollups() throws {
        let store = try EventStore(path: ":memory:")
        let start = local(2024, 1, 1, 20).epochMillis
        let end = start + 60_000
        let freezeTime = local(2024, 1, 2, 4).epochMillis
        _ = try store.record(flush(sentAt: start), serverTime: start)
        _ = try store.record(flush(sentAt: end, views: [closedView(id: "closed", start: start)]), serverTime: end)
        try store.setRawEventRetentionDays(0)

        // Age out the closed View's raw Events, then let a read past the target
        // hour cross the Day boundary. (A read, not a Flush at `freezeTime`:
        // the boundary freeze now waits for ingest to settle, and a Flush
        // landing right at the read would look like a backlog still draining.)
        try store.pruneRawEvents(now: Date(epochMillis: freezeTime))

        let segments = try store.segments(viewId: "closed")
        let range = DateRangeKind.custom(from: local(2024, 1, 1, 12), through: local(2024, 1, 1, 12))
        let slices = try store.slices(for: range, now: Date(epochMillis: freezeTime))
        let series = try store.dailySeries(for: range, now: Date(epochMillis: freezeTime))
        let frozenDays = try store.frozenDays()

        #expect(try store.counts().rawEvents == 0)
        #expect(segments.count == 1)
        #expect(segments[0].wallStartMs == start)
        #expect(segments[0].wallEndMs == end)
        #expect(frozenDays == [FrozenDay(label: "2024-01-01", dayStartMs: start, dayEndMs: freezeTime, watchedMs: 60_000, backgroundMs: 0)])
        #expect(slices == [TotalsSlice(service: "youtube", contentFormat: "standard", totals: Totals(watchedMs: 60_000))])
        #expect(series.map(\.label) == ["2024-01-01"])
        #expect(series.map(\.totalMs) == [60_000])
    }

    @Test("an open View keeps its old Events so a later Flush can recompute its Segment")
    func openViewKeepsHistoryUntilLaterFlushClosesIt() throws {
        let store = try EventStore(path: ":memory:")
        let start = local(2024, 1, 1, 12).epochMillis
        try store.setRawEventRetentionDays(0)
        let openView = FlushView(
            viewId: "open", service: "youtube", videoId: "v", url: "https://example.com/v",
            adapterId: "youtube", tabId: 1, startedAt: start, open: true,
            events: [
                RawEvent(seq: 1, type: .mediaFound, t: start, pos: 0),
                RawEvent(seq: 2, type: .play, t: start, pos: 0),
            ]
        )
        _ = try store.record(flush(sentAt: start + 60_000, views: [openView]), serverTime: start + 60_000)
        #expect(try store.counts().rawEvents == 2)

        let end = start + 120_000
        let closedView = FlushView(
            viewId: "open", service: "youtube", videoId: "v", url: "https://example.com/v",
            adapterId: "youtube", tabId: 1, startedAt: start, open: false,
            events: [RawEvent(seq: 3, type: .viewEnded, t: end, pos: 120, reason: "nav")]
        )
        _ = try store.record(flush(sentAt: end, views: [closedView]), serverTime: end + 1)

        let segments = try store.segments(viewId: "open")
        #expect(try store.counts().rawEvents == 0)
        #expect(segments.count == 1)
        #expect(segments[0].wallStartMs == start)
        #expect(segments[0].wallEndMs == end)
        #expect(segments[0].provisional == false)
    }

    @Test("By Service returns embedded YouTube watched time for the selected range")
    func embeddedYouTubeWatchedTimeUsesSelectedRange() throws {
        let now = local(2024, 1, 1, 14)
        let store = try EventStore(path: ":memory:")
        _ = try store.record(FlushEnvelope(schemaVersion: 1, flushId: UUID().uuidString, sentAt: local(2024, 1, 1, 11).epochMillis, agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"), views: []), serverTime: local(2024, 1, 1, 11).epochMillis)
        let embedded = FlushView(
            viewId: "embedded", service: "youtube", contentFormat: "standard", embedded: true,
            videoId: "embedded", url: "https://example.com/embed", adapterId: "youtube", tabId: 1,
            startedAt: local(2024, 1, 1, 12).epochMillis, open: false,
            events: [
                RawEvent(seq: 1, type: .mediaFound, t: local(2024, 1, 1, 12).epochMillis, pos: 0),
                RawEvent(seq: 2, type: .play, t: local(2024, 1, 1, 12).epochMillis, pos: 0),
                RawEvent(seq: 3, type: .viewEnded, t: local(2024, 1, 1, 12, 1).epochMillis, pos: 60, reason: "nav"),
            ]
        )
        let direct = FlushView(
            viewId: "direct", service: "youtube", contentFormat: "standard", embedded: false,
            videoId: "direct", url: "https://youtube.com/watch", adapterId: "youtube", tabId: 2,
            startedAt: local(2024, 1, 1, 13).epochMillis, open: false,
            events: [
                RawEvent(seq: 1, type: .mediaFound, t: local(2024, 1, 1, 13).epochMillis, pos: 0),
                RawEvent(seq: 2, type: .play, t: local(2024, 1, 1, 13).epochMillis, pos: 0),
                RawEvent(seq: 3, type: .viewEnded, t: local(2024, 1, 1, 13, 2).epochMillis, pos: 120, reason: "nav"),
            ]
        )
        _ = try store.record(FlushEnvelope(schemaVersion: 1, flushId: UUID().uuidString, sentAt: now.epochMillis, agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"), views: [embedded, direct]), serverTime: now.epochMillis)

        #expect(try store.embeddedYouTubeWatchedMs(for: .today, now: now) == 60_000)
    }

    @Test("By Service splits a YouTube Short into its own format slice from the /shorts/ URL")
    func byServiceSplitsShortsFromVideos() throws {
        let now = local(2024, 1, 1, 14)
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: local(2024, 1, 1, 11).epochMillis, views: []), serverTime: local(2024, 1, 1, 11).epochMillis)
        let short = FlushView(
            viewId: "short", service: "youtube.com", videoId: "s",
            url: "https://www.youtube.com/shorts/vFyggQD4psM", tabId: 1,
            startedAt: local(2024, 1, 1, 12).epochMillis, open: false, events: [
                RawEvent(seq: 1, type: .play, t: local(2024, 1, 1, 12).epochMillis, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: local(2024, 1, 1, 12, 1).epochMillis, pos: 60, reason: "nav"),
            ])
        let video = FlushView(
            viewId: "video", service: "youtube.com", videoId: "v",
            url: "https://www.youtube.com/watch?v=lP3_JgisNuM", tabId: 2,
            startedAt: local(2024, 1, 1, 13).epochMillis, open: false, events: [
                RawEvent(seq: 1, type: .play, t: local(2024, 1, 1, 13).epochMillis, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: local(2024, 1, 1, 13, 2).epochMillis, pos: 120, reason: "nav"),
            ])
        _ = try store.record(flush(sentAt: now.epochMillis, views: [short, video]), serverTime: now.epochMillis)

        let formats = try #require(
            store.displayServiceTotals(for: .today, now: now).first { $0.service == .youtube }
        ).formats
        let byFormat = Dictionary(uniqueKeysWithValues: formats.map { ($0.contentFormat, $0.totals.watchedMs) })
        #expect(byFormat["short"] == 60_000)
        #expect(byFormat["standard"] == 120_000)
    }

    @Test("History coverage interpolates the media span when a Day clips a Segment")
    func historyCoverageClipsMediaPositionAtDayBoundary() throws {
        let calendar = Calendar.current
        let clock = ManualClock(local(2024, 1, 2, 10, 1))
        let store = try EventStore(path: ":memory:")
        // Establish the existing Day before the boundary-crossing View begins.
        _ = try store.record(FlushEnvelope(schemaVersion: 1, flushId: UUID().uuidString, sentAt: local(2024, 1, 1, 12, 0).epochMillis, agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"), views: []), serverTime: local(2024, 1, 1, 12, 0).epochMillis)
        let start = local(2024, 1, 2, 3, 59).epochMillis
        let end = local(2024, 1, 2, 10, 1).epochMillis
        let view = FlushView(
            viewId: "boundary", service: "youtube", contentFormat: "standard", embedded: false,
            videoId: "v", url: "https://example.com/v", durationSec: 21_720, adapterId: "youtube",
            tabId: 1, startedAt: start, open: false,
            events: [
                RawEvent(seq: 1, type: .mediaFound, t: start, pos: 0),
                RawEvent(seq: 2, type: .play, t: start, pos: 0),
                RawEvent(seq: 3, type: .viewEnded, t: end, pos: 21_720, reason: "nav"),
            ]
        )
        _ = try store.record(FlushEnvelope(schemaVersion: 1, flushId: UUID().uuidString, sentAt: end, agent: .init(extInstanceId: "ext", extVersion: "1", browser: "chrome", os: "macOS"), views: [view]), serverTime: start)

        let day = local(2024, 1, 1, 0, 0)
        let history = try store.history(for: .custom(from: day, through: day), now: clock.now(), calendar: calendar)

        #expect(history.count == 1)
        let clippedVideo = try #require(history.first?.videos.first)
        #expect(clippedVideo.watchedMs == 21_660_000)
        #expect(clippedVideo.coverage == Double(21_660) / Double(21_720))
    }

    @Test("History coverage unions overlapping rewatches")
    func historyCoverageUnionsOverlappingRewatches() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        let view = FlushView(viewId: "rewatch", service: "youtube", videoId: "v", url: "https://example.com/v", durationSec: 120, adapterId: "youtube", tabId: 1, startedAt: start, open: false, events: [
            RawEvent(seq: 1, type: .mediaFound, t: start, pos: 0),
            RawEvent(seq: 2, type: .play, t: start, pos: 0),
            RawEvent(seq: 3, type: .seeked, t: start + 60_000, from: 60, to: 30),
            RawEvent(seq: 4, type: .viewEnded, t: start + 120_000, pos: 90, reason: "nav"),
        ])
        _ = try store.record(flush(sentAt: start + 120_000, views: [view]), serverTime: start + 120_000)

        let history = try store.history(for: .today, now: Date(epochMillis: start + 120_000))
        #expect(try #require(history.first?.videos.first).coverage == 0.75)
    }

    @Test("History recovers the Shorts format from a /shorts/ URL at read time")
    func historyRecoversShortsFormatFromURL() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        let short = FlushView(
            viewId: "short", service: "youtube.com", videoId: "s",
            url: "https://www.youtube.com/shorts/vFyggQD4psM", durationSec: 45, tabId: 1,
            startedAt: start, open: false, events: [
                RawEvent(seq: 1, type: .play, t: start, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: start + 30_000, pos: 30, reason: "nav"),
            ])
        let video = FlushView(
            viewId: "video", service: "youtube.com", videoId: "v",
            url: "https://www.youtube.com/watch?v=lP3_JgisNuM", durationSec: 600, tabId: 2,
            startedAt: start + 1, open: false, events: [
                RawEvent(seq: 1, type: .play, t: start + 1, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: start + 30_001, pos: 30, reason: "nav"),
            ])
        _ = try store.record(flush(sentAt: start + 60_000, views: [short, video]), serverTime: start + 60_000)

        let videos = try #require(store.history(for: .today, now: Date(epochMillis: start + 60_000)).first?.videos)
        #expect(videos.first { $0.videoId == "s" }?.contentFormat == "short")
        #expect(videos.first { $0.videoId == "v" }?.contentFormat == "standard")
    }

    @Test("readTimeContentFormat only rewrites a standard View on a /shorts/ path")
    func readTimeContentFormatRules() {
        #expect(EventStore.readTimeContentFormat(stored: "standard", url: "https://youtube.com/shorts/abc") == "short")
        #expect(EventStore.readTimeContentFormat(stored: "standard", url: "https://youtube.com/watch?v=abc") == "standard")
        // A live Short keeps "live" — that format is already trustworthy.
        #expect(EventStore.readTimeContentFormat(stored: "live", url: "https://youtube.com/shorts/abc") == "live")
    }

    @Test("History has no coverage for a live View")
    func historyLiveViewHasNoCoverage() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        let view = FlushView(viewId: "live", service: "youtube", contentFormat: "live", videoId: "v", url: "https://example.com/v", durationSec: 120, adapterId: "youtube", tabId: 1, startedAt: start, open: false, events: [
            RawEvent(seq: 1, type: .play, t: start, pos: 0), RawEvent(seq: 2, type: .viewEnded, t: start + 60_000, pos: 60, reason: "nav"),
        ])
        _ = try store.record(flush(sentAt: start + 60_000, views: [view]), serverTime: start + 60_000)
        #expect(try #require(store.history(for: .today, now: Date(epochMillis: start + 60_000)).first?.videos.first).coverage == nil)
    }

    @Test("History has no coverage without a known duration")
    func historyUnknownDurationHasNoCoverage() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        let view = FlushView(viewId: "unknown", service: "youtube", videoId: "v", url: "https://example.com/v", adapterId: "youtube", tabId: 1, startedAt: start, open: false, events: [
            RawEvent(seq: 1, type: .play, t: start, pos: 0), RawEvent(seq: 2, type: .viewEnded, t: start + 60_000, pos: 60, reason: "nav"),
        ])
        _ = try store.record(flush(sentAt: start + 60_000, views: [view]), serverTime: start + 60_000)
        #expect(try #require(store.history(for: .today, now: Date(epochMillis: start + 60_000)).first?.videos.first).coverage == nil)
    }

    @Test("History shows a View in each activity Day it crosses with clipped watched time")
    func historySplitsViewAcrossForcedActivityDayBoundary() throws {
        let calendar = Calendar.current
        let start = local(2024, 1, 2, 3, 59).epochMillis
        let end = local(2024, 1, 2, 10, 1).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: local(2024, 1, 1, 12).epochMillis, views: []), serverTime: local(2024, 1, 1, 12).epochMillis)
        let view = FlushView(viewId: "crossing", service: "youtube", videoId: "v", url: "https://example.com/v", adapterId: "youtube", tabId: 1, startedAt: start, open: false, events: [
            RawEvent(seq: 1, type: .play, t: start, pos: 0), RawEvent(seq: 2, type: .viewEnded, t: end, pos: 21_720, reason: "nav"),
        ])
        _ = try store.record(flush(sentAt: end, views: [view]), serverTime: start)
        let history = try store.history(for: .custom(from: local(2024, 1, 1, 0), through: local(2024, 1, 2, 0)), now: local(2024, 1, 2, 10, 1), calendar: calendar)
        // Newest Day first.
        #expect(history.map(\.label) == ["2024-01-02", "2024-01-01"])
        #expect(history.map(\.watchedMs) == [60_000, 21_660_000])
        #expect(history.allSatisfy { $0.videos.map(\.videoId) == ["v"] })
    }

    @Test("History lists the newest Day first across a multi-day range")
    func historyListsNewestDayFirst() throws {
        let calendar = Calendar.current
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: local(2024, 1, 1, 8).epochMillis, views: []), serverTime: local(2024, 1, 1, 8).epochMillis)
        for day in 1...3 {
            let start = local(2024, 1, day, 12).epochMillis
            let view = FlushView(
                viewId: "v\(day)", service: "youtube", videoId: "vid\(day)",
                url: "https://youtube.com/watch?v=\(day)", durationSec: 120, adapterId: "youtube",
                tabId: 1, startedAt: start, open: false, events: [
                    RawEvent(seq: 1, type: .play, t: start, pos: 0),
                    RawEvent(seq: 2, type: .viewEnded, t: start + 30_000, pos: 30, reason: "nav"),
                ])
            _ = try store.record(flush(sentAt: start + 30_000, views: [view]), serverTime: start + 30_000)
        }
        let history = try store.history(for: .custom(from: local(2024, 1, 1, 0), through: local(2024, 1, 3, 0)), now: local(2024, 1, 3, 20), calendar: calendar)
        #expect(history.map(\.label) == ["2024-01-03", "2024-01-02", "2024-01-01"])
    }

    @Test("a buffered backlog draining in per-View order does not freeze a Day at the bare target hour")
    func backlogDrainDefersDayFreeze() throws {
        let store = try EventStore(path: ":memory:")
        // The Day timeline bootstraps at 04:00 on Jan 2.
        _ = try store.record(flush(sentAt: local(2024, 1, 2, 4).epochMillis, views: []), serverTime: local(2024, 1, 2, 4).epochMillis)

        // It is now 04:30 on Jan 3 — past the 04:00 target hour — and a long
        // offline stretch's backlog drains, one View per Flush, in no useful
        // order. First out: a View whose whole life is after 04:00 Jan 3. If
        // `record` decided the boundary here it would see no activity at 04:00
        // and pin the Jan 2 Day to it — the bug.
        let now = local(2024, 1, 3, 4, 30)
        func replayView(_ id: String, from startMs: Int, forMs durationMs: Int) -> FlushView {
            FlushView(
                viewId: id, service: "youtube", videoId: id, url: "https://youtube.com/watch?v=\(id)",
                durationSec: 3_600, adapterId: "youtube", tabId: 1, startedAt: startMs, open: false,
                events: [
                    RawEvent(seq: 1, type: .play, t: startMs, pos: 0),
                    RawEvent(seq: 2, type: .viewEnded, t: startMs + durationMs, pos: Double(durationMs) / 1000, reason: "nav"),
                ])
        }
        _ = try store.record(flush(sentAt: now.epochMillis, views: [
            replayView("after", from: local(2024, 1, 3, 4, 5).epochMillis, forMs: 300_000),
        ]), serverTime: now.epochMillis)
        _ = try store.record(flush(sentAt: now.epochMillis, views: [
            replayView("straddle", from: local(2024, 1, 3, 3, 50).epochMillis, forMs: 1_200_000), // 03:50 → 04:10
        ]), serverTime: now.epochMillis)

        // No Flush froze anything.
        #expect(try store.frozenDays().isEmpty)

        // The read that drives the UI now evaluates the boundary, with the
        // whole backlog present: activity straddled 04:00 Jan 3, so the Jan 2
        // Day slides past it and stays open — never pinned to the target hour,
        // and the 03:50 Jan 3 View lands under the Jan 2 label.
        let today = try #require(store.history(for: .today, now: now).first)
        #expect(try store.frozenDays().isEmpty)
        #expect(today.label == "2024-01-02")
        #expect(today.videos.contains { $0.videoId == "straddle" })
        #expect(today.videos.contains { $0.videoId == "after" })
    }

    @Test("History folds every View of one video that Day into a single row")
    func historyFoldsRepeatViewsOfOneVideo() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        // The same Short, watched twice a minute apart — two Views, one video.
        let first = FlushView(
            viewId: "v1", service: "youtube.com", videoId: "s",
            url: "https://www.youtube.com/shorts/abc", durationSec: 60, tabId: 1,
            startedAt: start, open: false, events: [
                RawEvent(seq: 1, type: .play, t: start, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: start + 20_000, pos: 20, reason: "nav"),
            ])
        let second = FlushView(
            viewId: "v2", service: "youtube.com", videoId: "s",
            url: "https://www.youtube.com/shorts/abc", durationSec: 60, tabId: 1,
            startedAt: start + 60_000, open: false, events: [
                RawEvent(seq: 1, type: .play, t: start + 60_000, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: start + 90_000, pos: 30, reason: "nav"),
            ])
        _ = try store.record(flush(sentAt: start + 120_000, views: [first, second]), serverTime: start + 120_000)

        let videos = try #require(store.history(for: .today, now: Date(epochMillis: start + 120_000)).first?.videos)
        #expect(videos.count == 1)
        let row = try #require(videos.first)
        #expect(row.watchCount == 2)
        #expect(row.watchedMs == 50_000)
        // Coverage unions the two passes: 0–20s then 0–30s = 30s of a 60s Short.
        #expect(row.coverage == 0.5)
    }

    @Test("History sorts the currently-playing video first, then by last watched")
    func historySortsPlayingVideoFirst() throws {
        let start = local(2024, 1, 1, 12).epochMillis
        let now = start + 600_000
        let store = try EventStore(path: ":memory:")
        _ = try store.record(flush(sentAt: start - 1, views: []), serverTime: start - 1)
        // A long video opened first, still playing at `now`.
        let playing = FlushView(
            viewId: "long", service: "youtube", videoId: "long",
            url: "https://youtube.com/watch?v=long", durationSec: 3_600, adapterId: "youtube",
            tabId: 1, startedAt: start, open: true, events: [
                RawEvent(seq: 1, type: .play, t: start, pos: 0),
                RawEvent(seq: 2, type: .sample, t: now - 1_000, pos: 599, playing: true, visible: true),
            ])
        // A Short watched in the middle and closed — more recent start, older last-watch.
        let short = FlushView(
            viewId: "s1", service: "youtube.com", videoId: "s",
            url: "https://www.youtube.com/shorts/abc", durationSec: 30, tabId: 2,
            startedAt: start + 120_000, open: false, events: [
                RawEvent(seq: 1, type: .play, t: start + 120_000, pos: 0),
                RawEvent(seq: 2, type: .viewEnded, t: start + 150_000, pos: 30, reason: "nav"),
            ])
        _ = try store.record(flush(sentAt: now, views: [playing, short]), serverTime: now)

        let videos = try #require(store.history(for: .today, now: Date(epochMillis: now)).first?.videos)
        #expect(videos.map(\.videoId) == ["long", "s"])
        #expect(videos.first?.isPlaying == true)
    }
}
