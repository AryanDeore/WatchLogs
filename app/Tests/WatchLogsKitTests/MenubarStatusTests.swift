import Foundation
import Testing
@testable import WatchLogsKit

@Suite("Menubar status line")
struct MenubarStatusTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("no flush yet reads as needs-pairing")
    func neverFlushed() {
        let status = MenubarStatus.evaluate(lastFlushAt: nil, now: epoch)
        #expect(status == .notPaired)
        #expect(status.line.contains("Not paired"))
    }

    @Test("a recent flush reads as connected with the age in seconds")
    func recentFlush() {
        let status = MenubarStatus.evaluate(
            lastFlushAt: epoch,
            now: epoch.addingTimeInterval(3),
            staleAfter: 15
        )
        #expect(status == .connected(secondsSinceLastFlush: 3))
        #expect(status.line == "Connected · last flush 3s ago")
    }

    @Test("a flush older than the stale window reads as disconnected")
    func staleFlush() {
        let status = MenubarStatus.evaluate(
            lastFlushAt: epoch,
            now: epoch.addingTimeInterval(42),
            staleAfter: 15
        )
        #expect(status == .disconnected(secondsSinceLastFlush: 42))
        #expect(status.line == "Disconnected · last flush 42s ago")
    }

    @Test("exactly at the stale boundary still counts as connected")
    func atBoundary() {
        let status = MenubarStatus.evaluate(
            lastFlushAt: epoch,
            now: epoch.addingTimeInterval(15),
            staleAfter: 15
        )
        #expect(status == .connected(secondsSinceLastFlush: 15))
    }

    @Test("an idle browser's 30s sweep gap still reads as connected")
    func idleSweepGap() {
        let status = MenubarStatus.evaluate(lastFlushAt: epoch, now: epoch.addingTimeInterval(31))
        #expect(status == .connected(secondsSinceLastFlush: 31))
    }

    @Test("a last-flush timestamp in the future clamps to zero")
    func futureClamps() {
        let status = MenubarStatus.evaluate(
            lastFlushAt: epoch.addingTimeInterval(5),
            now: epoch
        )
        #expect(status == .connected(secondsSinceLastFlush: 0))
    }

    @Test("a long silence is humanised to minutes")
    func longSilence() {
        let status = MenubarStatus.evaluate(
            lastFlushAt: epoch,
            now: epoch.addingTimeInterval(600)
        )
        #expect(status.line == "Disconnected · last flush 10 min ago")
    }
}
