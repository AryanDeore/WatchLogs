import Foundation
import Testing
@testable import WatchLogsKit

/// Seam 1: real Flush bodies in over `POST /v1/flush`, read-model totals out.
/// Nothing here reaches below the seam — no Segment lists, no SQL.
@Suite("Watched time from the Event log", .serialized)
struct WatchedTimeTests {
    /// The window the schema example's timestamps sit in.
    private let exampleRange = DateRange(startMs: 1_788_026_000_000, endMs: 1_788_027_000_000)

    private func post(_ body: Data, to service: LoopbackTransport, using client: RawHTTPClient) throws -> RawHTTPClient.Response {
        try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(service.pairing().token)", "Content-Type": "application/json"],
            body: body
        )
    }

    // MARK: - The schema example

    @Test("the two-View example from SCHEMA.md produces the expected watched and background totals")
    func schemaExampleTotals() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        let response = try post(FlushJSON.schemaExample, to: service, using: client)
        #expect(response.status == 200)

        // View 1: 401→413 s and 413→418 s, split by the seek = 17 s Watched.
        // View 2: 419→426 s Watched, then hidden, 426→434 s background.
        let totals = try store.totals(in: exampleRange)
        #expect(totals.watchedMs == 24_000)
        #expect(totals.backgroundMs == 8_000)
        #expect(totals.watchedSeconds == 24)
        #expect(totals.backgroundSeconds == 8)
    }

    @Test("the Ack returns the highest accepted seq per View")
    func ackSeqPerView() throws {
        let (service, client, _) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        let response = try post(FlushJSON.schemaExample, to: service, using: client)
        let views = try #require(response.json()?["views"] as? [[String: Any]])
        #expect(views.count == 2)
        #expect(views[0]["viewId"] as? String == FlushJSON.firstViewId)
        #expect(views[0]["ackSeq"] as? Int == 8)
        #expect(views[1]["viewId"] as? String == FlushJSON.secondViewId)
        #expect(views[1]["ackSeq"] as? Int == 7)
    }

    // MARK: - At-least-once

    @Test("re-posting a Flush with the same flushId replays the Ack and changes no total")
    func replayedFlushChangesNothing() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_788_026_435))
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        let first = try post(FlushJSON.schemaExample, to: service, using: client)
        let afterFirst = try store.totals(in: exampleRange)
        let rowsAfterFirst = try store.counts()

        clock.advance(by: 90)
        let resent = try post(FlushJSON.schemaExample, to: service, using: client)

        #expect(resent.status == 200)
        #expect(resent.bodyString == first.bodyString)
        // The replayed Ack carries the *first* delivery's serverTime.
        #expect(resent.json()?["serverTime"] as? Int == 1_788_026_435_000)
        #expect(try store.totals(in: exampleRange) == afterFirst)
        #expect(try store.counts() == rowsAfterFirst)
    }

    @Test("an overlapping re-send under a new flushId is stored but de-duplicated")
    func overlappingResendDoesNotDoubleCount() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        // The App's Ack was lost after a partial success, so the Extension
        // rebuilds the batch from its buffer: events 3–8 overlap what it already
        // sent, under a fresh flushId.
        _ = try post(FlushJSON.firstViewFlush(seqRange: 1...5), to: service, using: client)
        _ = try post(FlushJSON.firstViewFlush(seqRange: 3...8), to: service, using: client)

        // Same answer as one clean delivery of the whole log.
        let (reference, referenceClient, referenceStore) = try LoopbackServerTests.makeService()
        defer { reference.stop() }
        _ = try post(FlushJSON.firstViewFlush(seqRange: 1...8), to: reference, using: referenceClient)

        #expect(try store.totals(in: exampleRange) == referenceStore.totals(in: exampleRange))
        #expect(try store.totals(in: exampleRange).watchedMs == 17_000)
        // The log kept both deliveries — it is append-only and assumes nothing.
        #expect(try store.counts().rawEvents == 11)
        #expect(try store.counts().segments == 2)
    }

    @Test("a crash-recovery Flush hours later recomputes the View without inflating it")
    func lateCrashRecoveryFlushIsIdempotent() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        // The browser died after seq 5. What the App had at the time is an open
        // View whose tail is provisional.
        _ = try post(FlushJSON.firstViewFlush(seqRange: 1...5), to: service, using: client)
        #expect(try store.totals(in: exampleRange).watchedMs == 10_000)

        // Hours later the Extension comes back and flushes the recovered tail.
        _ = try post(FlushJSON.crashRecoveredTail, to: service, using: client)

        // The View is recomputed from its whole log: the provisional tail is
        // replaced, and the recovered end closes at the last sample (411 s), not
        // at the hour-late stamp.
        let totals = try store.totals(in: exampleRange)
        #expect(totals.watchedMs == 10_000)
        #expect(try store.totals(in: DateRange(startMs: 0, endMs: 4_000_000_000_000)).watchedMs == 10_000)
    }

    // MARK: - Open Views

    @Test("the open View's trailing Segment is provisional and is replaced by the next Flush")
    func provisionalTailIsReplaced() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        _ = try post(FlushJSON.schemaExample, to: service, using: client)

        // View 2 is still running: its `watched` head is final, its `background`
        // tail is provisional and stops at the last heartbeat.
        let openView = try store.segments(viewId: FlushJSON.secondViewId)
        #expect(openView.map(\.kind) == [.watched, .background])
        #expect(openView.map(\.provisional) == [false, true])
        #expect(openView[1].wallEndMs == 1_788_026_434_000)

        // The View plays on for another 6 s in the background, then ends.
        _ = try post(FlushJSON.secondViewEnding, to: service, using: client)

        let closedView = try store.segments(viewId: FlushJSON.secondViewId)
        #expect(closedView.count == 2)
        #expect(closedView.allSatisfy { !$0.provisional })
        #expect(closedView[1].wallEndMs == 1_788_026_440_000)
        #expect(try store.totals(in: exampleRange).backgroundMs == 14_000)
        #expect(try store.totals(in: exampleRange).watchedMs == 24_000)
    }

    // MARK: - Read-time clipping and "today"

    @Test("a Segment straddling the window edge contributes only its overlap")
    func segmentsAreClippedAtReadTime() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        _ = try post(FlushJSON.schemaExample, to: service, using: client)

        // A window that starts halfway through View 1's first Segment
        // (401 s → 413 s) and ends halfway through its second (413 s → 418 s).
        let window = DateRange(startMs: 1_788_026_405_000, endMs: 1_788_026_415_000)
        #expect(try store.totals(in: window).watchedMs == 10_000)
    }

    @Test("the menubar's Watched today number is totals(today)")
    func watchedTodayMatchesTheReadModel() throws {
        // Noon, so the open Day bootstraps here rather than crossing its own
        // target hour partway through the test.
        let noon = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let clock = ManualClock(noon)
        let (service, client, store) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        _ = try post(FlushJSON.oneMinuteSession(startingAt: noon.epochMillis), to: service, using: client)
        // The open Day's live window is clipped to "now" (ADR 0001's
        // `openDayTotals()`), so the clock must reach the session's end.
        clock.advance(by: 60)

        let totals = try service.todayTotals()
        #expect(totals.watchedMs == 60_000)
        #expect(try store.totals(in: DateRange(startMs: noon.epochMillis, endMs: clock.now().epochMillis)) == totals)
        #expect(WatchedTimeLine.today(totals) == "Watched today · 1m")
    }

    @Test("yesterday's session is not in today's total")
    func totalsAreScopedToTheirDay() throws {
        let noon = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let clock = ManualClock(noon)
        let (service, client, _) = try LoopbackServerTests.makeService(clock: clock)
        defer { service.stop() }

        let yesterdayNoon = noon.addingTimeInterval(-86_400)
        _ = try post(FlushJSON.oneMinuteSession(startingAt: yesterdayNoon.epochMillis), to: service, using: client)
        clock.advance(by: 3600)

        // The open Day bootstrapped at `noon` (this store's first-ever
        // record), a full day after the posted session.
        #expect(try service.todayTotals().watchedMs == 0)
    }

    // MARK: - Across a restart

    @Test("totals survive the App quitting — the log and its Segments are on disk")
    func totalsSurviveARestart() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlogs-test-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        let port = Int.random(in: 49_200..<52_000)
        let service = try LoopbackTransport(
            version: "0.1.0",
            tokenStore: InMemoryTokenStore(),
            store: try EventStore(path: path),
            config: LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        )
        try service.start()
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
        _ = try post(FlushJSON.schemaExample, to: service, using: client)
        service.stop()

        let reopened = try EventStore(path: path)
        #expect(try reopened.totals(in: exampleRange).watchedMs == 24_000)
        #expect(try reopened.totals(in: exampleRange).backgroundMs == 8_000)
    }

    // MARK: - Rejections store nothing

    @Test("a Flush whose View is missing a required field is 400 and stores nothing")
    func malformedViewIsRejectedWhole() throws {
        let (service, client, store) = try LoopbackServerTests.makeService()
        defer { service.stop() }

        let response = try post(FlushJSON.viewMissingService, to: service, using: client)
        #expect(response.status == 400)
        #expect(response.json()?["error"] as? String == "view missing service")
        #expect(try store.counts() == EventStore.Counts())
    }
}

/// Flush bodies as the Extension would send them.
enum FlushJSON {
    static let firstViewId = "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40"
    static let secondViewId = "view-3b7c88e1-9a02-4f31-8d77-2e5b4c9a1f66"

    /// The concrete two-View example from `prototypes/message-schema/SCHEMA.md`,
    /// verbatim — including `artworkUrl`, which #4 removed from the schema and
    /// the App must therefore ignore rather than trip over.
    static let schemaExample = Data(#"""
    {
      "schemaVersion": 1,
      "flushId": "f1e2d3c4-5b6a-4c7d-8e9f-0a1b2c3d4e5f",
      "sentAt": 1788026435000,
      "agent": {
        "extInstanceId": "ext-inst-7f3a9c21",
        "extVersion": "0.1.0",
        "browser": "chrome",
        "os": "macOS 15.6"
      },
      "views": [
        {
          "viewId": "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40",
          "service": "youtube",
          "contentFormat": "standard",
          "embedded": false,
          "videoId": "dQw4w9WgXcQ",
          "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "title": "Never Gonna Give You Up",
          "author": "Rick Astley",
          "artworkUrl": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
          "durationSec": 213,
          "metadataSource": "adapter",
          "adapterId": "youtube",
          "tabId": 41,
          "startedAt": 1788026400000,
          "open": false,
          "previousViewId": null,
          "events": [
            { "seq": 1, "type": "mediaFound",     "t": 1788026400000, "pos": 0 },
            { "seq": 2, "type": "metadataChange", "t": 1788026400500, "pos": 0,
              "changed": { "title": "Never Gonna Give You Up", "author": "Rick Astley",
                           "durationSec": 213 } },
            { "seq": 3, "type": "play",    "t": 1788026401000, "pos": 0 },
            { "seq": 4, "type": "sample",  "t": 1788026406000, "pos": 5.0,  "playing": true, "visible": true },
            { "seq": 5, "type": "sample",  "t": 1788026411000, "pos": 10.0, "playing": true, "visible": true },
            { "seq": 6, "type": "seeked",  "t": 1788026413000, "pos": 45.2, "from": 10.6, "to": 45.2 },
            { "seq": 7, "type": "sample",  "t": 1788026416000, "pos": 48.2, "playing": true, "visible": true },
            { "seq": 8, "type": "viewEnded", "t": 1788026418000, "pos": 50.2, "reason": "video-changed" }
          ]
        },
        {
          "viewId": "view-3b7c88e1-9a02-4f31-8d77-2e5b4c9a1f66",
          "service": "youtube",
          "contentFormat": "standard",
          "embedded": false,
          "videoId": "kJQP7kiw5Fk",
          "url": "https://www.youtube.com/watch?v=kJQP7kiw5Fk",
          "title": "Luis Fonsi - Despacito ft. Daddy Yankee",
          "author": "Luis Fonsi",
          "durationSec": 282,
          "metadataSource": "adapter",
          "adapterId": "youtube",
          "tabId": 41,
          "startedAt": 1788026418000,
          "open": true,
          "previousViewId": "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40",
          "events": [
            { "seq": 1, "type": "mediaFound", "t": 1788026418000, "pos": 0 },
            { "seq": 2, "type": "play",       "t": 1788026419000, "pos": 0 },
            { "seq": 3, "type": "sample",     "t": 1788026424000, "pos": 5.0,  "playing": true, "visible": true },
            { "seq": 4, "type": "hidden",     "t": 1788026426000, "pos": 7.0 },
            { "seq": 5, "type": "sample",     "t": 1788026429000, "pos": 10.0, "playing": true, "visible": false },
            { "seq": 6, "type": "ratechange", "t": 1788026431000, "pos": 12.0, "rate": 2.0 },
            { "seq": 7, "type": "sample",     "t": 1788026434000, "pos": 18.0, "playing": true, "visible": false }
          ]
        }
      ]
    }
    """#.utf8)

    /// The example's first View carrying only `seqRange` of its Events — how a
    /// live Flush arrives, and how a re-send after a lost Ack overlaps.
    static func firstViewFlush(seqRange: ClosedRange<Int>) -> Data {
        let events = [
            #"{ "seq": 1, "type": "mediaFound", "t": 1788026400000, "pos": 0 }"#,
            #"{ "seq": 2, "type": "metadataChange", "t": 1788026400500, "pos": 0 }"#,
            #"{ "seq": 3, "type": "play", "t": 1788026401000, "pos": 0 }"#,
            #"{ "seq": 4, "type": "sample", "t": 1788026406000, "pos": 5.0, "playing": true, "visible": true }"#,
            #"{ "seq": 5, "type": "sample", "t": 1788026411000, "pos": 10.0, "playing": true, "visible": true }"#,
            #"{ "seq": 6, "type": "seeked", "t": 1788026413000, "pos": 45.2, "from": 10.6, "to": 45.2 }"#,
            #"{ "seq": 7, "type": "sample", "t": 1788026416000, "pos": 48.2, "playing": true, "visible": true }"#,
            #"{ "seq": 8, "type": "viewEnded", "t": 1788026418000, "pos": 50.2, "reason": "video-changed" }"#,
        ]
        let closed = seqRange.contains(8)
        return envelope(views: [
            view(
                id: firstViewId,
                open: !closed,
                events: seqRange.map { events[$0 - 1] }
            )
        ])
    }

    /// The tail the Extension re-flushes after the browser died: a
    /// `crash-recovered` end stamped at the last `sample`, arriving an hour late.
    static let crashRecoveredTail = envelope(views: [
        view(
            id: firstViewId,
            open: false,
            events: [
                #"{ "seq": 6, "type": "viewEnded", "t": 1788026411000, "pos": 10.0, "reason": "crash-recovered" }"#
            ]
        )
    ])

    /// The rest of the example's second View: six more seconds in a hidden tab,
    /// then a clean end.
    static let secondViewEnding = envelope(views: [
        view(
            id: secondViewId,
            open: false,
            events: [
                #"{ "seq": 8, "type": "sample", "t": 1788026439000, "pos": 23.0, "playing": true, "visible": false }"#,
                #"{ "seq": 9, "type": "viewEnded", "t": 1788026440000, "pos": 24.0, "reason": "nav" }"#,
            ]
        )
    ])

    /// One minute of foreground playback starting at `startMs`.
    static func oneMinuteSession(startingAt startMs: Int) -> Data {
        var events = [
            #"{ "seq": 1, "type": "mediaFound", "t": \#(startMs), "pos": 0 }"#,
            #"{ "seq": 2, "type": "play", "t": \#(startMs), "pos": 0 }"#,
        ]
        var seq = 3
        for second in stride(from: 5, through: 55, by: 5) {
            events.append(
                #"{ "seq": \#(seq), "type": "sample", "t": \#(startMs + second * 1000), "pos": \#(second), "playing": true, "visible": true }"#
            )
            seq += 1
        }
        events.append(#"{ "seq": \#(seq), "type": "viewEnded", "t": \#(startMs + 60_000), "pos": 60, "reason": "nav" }"#)
        return envelope(views: [view(id: "view-\(startMs)", open: false, events: events)])
    }

    static let viewMissingService = Data(#"""
    {"schemaVersion":1,"flushId":"\#(UUID().uuidString)","sentAt":1788026435000,
     "agent":{"extInstanceId":"e","extVersion":"0.1.0","browser":"chrome","os":"macOS"},
     "views":[{"viewId":"view-1","contentFormat":"standard","embedded":false,"videoId":"v",
               "url":"https://example.com/v","tabId":1,"startedAt":1788026400000,"open":true,
               "events":[{"seq":1,"type":"play","t":1788026401000,"pos":0}]}]}
    """#.utf8)

    static func envelope(flushId: String = UUID().uuidString, views: [String]) -> Data {
        Data(#"""
        {"schemaVersion":1,"flushId":"\#(flushId)","sentAt":1788026435000,
         "agent":{"extInstanceId":"ext-inst-7f3a9c21","extVersion":"0.1.0","browser":"chrome","os":"macOS 15.6"},
         "views":[\#(views.joined(separator: ","))]}
        """#.utf8)
    }

    static func view(id: String, open: Bool, events: [String]) -> String {
        #"""
        {"viewId":"\#(id)","service":"youtube","contentFormat":"standard","embedded":false,
         "videoId":"dQw4w9WgXcQ","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
         "title":"Never Gonna Give You Up","author":"Rick Astley","durationSec":213,
         "metadataSource":"adapter","adapterId":"youtube","tabId":41,"startedAt":1788026400000,
         "open":\#(open),"previousViewId":null,"events":[\#(events.joined(separator: ","))]}
        """#
    }
}
