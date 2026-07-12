//
//  probe.swift
//  WatchLogs
//
//  Created by Aryan Deore on 7/9/26.
//

import Foundation
import AppKit

class NowPlayingProbe {
    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private let mediaRemote = MediaRemoteBridge()
    private let tracker: PlaybackTracker
    private let store = TrackingStore()
    private let iso8601Formatter = ISO8601DateFormatter()

    init() {
        self.tracker = PlaybackTracker(pollInterval: pollInterval) { [store] event in
            store.handle(event)
        }
    }

    private func poll() {
        mediaRemote.fetchNowPlayingInfo { [weak self] info in
            guard let self else { return }
            let snapshot = self.makeSnapshot(from: info)
            self.log(snapshot)
            self.tracker.consume(snapshot)
        }
    }

    private func makeSnapshot(from info: [String: Any]?) -> NowPlayingSnapshot {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let sourceBundleID = (info?["bundleIdentifier"] as? String) ?? frontmostBundleID

        return NowPlayingSnapshot(
            timestamp: Date(),
            title: info?["title"] as? String,
            elapsedTime: info?["elapsedTime"] as? Double,
            duration: info?["duration"] as? Double,
            playbackRate: info?["playbackRate"] as? Double,
            sourceBundleID: sourceBundleID,
            frontmostBundleID: frontmostBundleID
        )
    }

    private func log(_ snapshot: NowPlayingSnapshot) {
        let ts = iso8601Formatter.string(from: snapshot.timestamp)
        let elapsed = snapshot.elapsedTime.map { String($0) } ?? "nil"
        let rate = snapshot.playbackRate.map { String($0) } ?? "nil"
        let duration = snapshot.duration.map { String($0) } ?? "nil"
        let title = snapshot.title ?? "nil"
        let sourceBundleID = snapshot.sourceBundleID ?? "nil"
        let frontmostBundleID = snapshot.frontmostBundleID ?? "nil"

        print("[\(ts)] title=\(title) elapsed=\(elapsed) rate=\(rate) duration=\(duration) sourceBundleID=\(sourceBundleID) frontmostBundleID=\(frontmostBundleID)")
    }

    func start() {
        if timer != nil {
            return
        }

        poll() // immediate bootstrap poll so already-playing media is captured quickly

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
