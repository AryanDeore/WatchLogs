import Foundation
import Testing
@testable import WatchLogsKit

/// Finding a View by hand, which is the first step of every investigation that
/// starts from "this row looks wrong".
///
/// The failure this suite exists to prevent is silent: a search that finds
/// nothing reads as "that video was never recorded", not as "you typed a
/// different dash", and there is nothing on screen to tell the two apart.
@Suite("View lookup")
struct ViewLookupTests {
    private func store(titles: [String]) throws -> EventStore {
        let store = try EventStore(path: ":memory:")
        let start = 1_788_026_400_000
        let views = titles.enumerated().map { index, title in
            FlushView(
                viewId: "view-\(index)",
                service: "youtube",
                videoId: "vid-\(index)",
                url: "https://youtube.com/watch?v=vid-\(index)",
                title: title,
                author: "A Channel",
                tabId: 1,
                startedAt: start + index * 1000,
                open: false,
                events: [
                    RawEvent(seq: 1, type: .mediaFound, t: start + index * 1000, pos: 0),
                    RawEvent(seq: 2, type: .play, t: start + index * 1000, pos: 0),
                    RawEvent(seq: 3, type: .viewEnded, t: start + index * 1000 + 60_000, pos: 60, reason: "nav"),
                ]
            )
        }
        _ = try store.record(
            FlushEnvelope(
                schemaVersion: 1,
                flushId: UUID().uuidString,
                sentAt: start,
                agent: .init(extInstanceId: "ext-1", extVersion: "0.1.0", browser: "chrome", os: "macOS"),
                views: views
            ),
            serverTime: start
        )
        return store
    }

    private func titles(_ records: [ViewRecord]) -> [String] {
        records.compactMap(\.title)
    }

    // The real one: YouTube titles are full of em dashes, and nobody types an
    // em dash. Under a plain substring match this returned nothing at all.
    @Test("an ordinary hyphen finds a title written with an em dash")
    func hyphenFindsEmDash() throws {
        let store = try store(titles: ["MoErgo Go60 — long term review"])

        #expect(titles(try store.viewRecords(matching: "MoErgo Go60 - long term review")).count == 1)
        #expect(titles(try store.viewRecords(matching: "MoErgo Go60 — long term review")).count == 1)
        #expect(titles(try store.viewRecords(matching: "moergo go60")).count == 1)
    }

    @Test("words may arrive in any order, and half a title is enough")
    func wordsInAnyOrder() throws {
        let store = try store(titles: ["MoErgo Go60 — long term review"])

        #expect(titles(try store.viewRecords(matching: "review go60")).count == 1)
        #expect(titles(try store.viewRecords(matching: "long review")).count == 1)
    }

    @Test("every word has to match, so a query stays a filter")
    func everyWordMustMatch() throws {
        let store = try store(titles: [
            "MoErgo Go60 — long term review",
            "One Surprise After Another - MoErgo Go60 Review",
        ])

        #expect(titles(try store.viewRecords(matching: "MoErgo")).count == 2)
        #expect(titles(try store.viewRecords(matching: "MoErgo long term")) == ["MoErgo Go60 — long term review"])
        #expect(titles(try store.viewRecords(matching: "MoErgo surprise")).count == 1)
        #expect(titles(try store.viewRecords(matching: "MoErgo nonsense")).isEmpty)
    }

    // A UUID is one word full of hyphens: trimming punctuation from the ends of
    // a word must not take the ones in the middle.
    @Test("a view id still matches whole or by prefix")
    func viewIdStillMatches() throws {
        let store = try store(titles: ["Something"])
        let id = try #require(try store.viewRecords().first?.viewId)

        #expect(try store.viewRecords(matching: id).count == 1)
        #expect(try store.viewRecords(matching: String(id.prefix(4))).count == 1)
    }

    // `%` and `_` are LIKE's own wildcards. Unescaped, a query containing one
    // quietly matches far more than it says — the kind of wrong answer that
    // looks like a right one.
    @Test("LIKE's own wildcards inside a word are matched literally")
    func wildcardsAreLiteral() throws {
        let store = try store(titles: ["a_b marker", "axb marker", "a%b marker", "azzb marker"])

        #expect(titles(try store.viewRecords(matching: "a_b")) == ["a_b marker"])
        #expect(titles(try store.viewRecords(matching: "a%b")) == ["a%b marker"])
        // And the ordinary case still works: four titles share "marker".
        #expect(try store.viewRecords(matching: "marker").count == 4)
    }

    @Test("an empty or punctuation-only query is the most recent Views")
    func emptyQueryIsRecent() throws {
        let store = try store(titles: ["First", "Second", "Third"])

        #expect(try store.viewRecords().count == 3)
        #expect(try store.viewRecords(matching: "   ").count == 3)
        #expect(try store.viewRecords(matching: "—").count == 3)
        // Newest first, so the top of the list is where you just were.
        #expect(titles(try store.viewRecords(limit: 1)) == ["Third"])
    }
}
