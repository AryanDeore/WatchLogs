//
//  PlaybackTracker.swift
//  WatchLogs
//
//  Created by Pi on 7/11/26.
//

import Foundation

final class PlaybackTracker {
    private struct Session {
        let id: UUID
        let title: String
        let sourceBundleID: String
        let startedAt: Date
        let durationTotal: Double?
    }

    private let pollInterval: TimeInterval
    private let forwardSeekThreshold: Double
    private let backwardSeekThreshold: Double
    private let emit: (TrackerEvent) -> Void
    private let staleWhilePlayingLimit = 3

    private var currentSession: Session?
    private var openSegmentStartSec: Double?
    private var openSegmentStartedAt: Date?
    private var previousSnapshot: NowPlayingSnapshot?
    private var staleWhilePlayingCount: Int = 0
    private var observedMinElapsed: Double?
    private var observedMaxElapsed: Double?

    init(
        pollInterval: TimeInterval,
        forwardSeekThreshold: Double = 5.0,
        backwardSeekThreshold: Double = 1.0,
        emit: @escaping (TrackerEvent) -> Void
    ) {
        self.pollInterval = pollInterval
        self.forwardSeekThreshold = forwardSeekThreshold
        self.backwardSeekThreshold = backwardSeekThreshold
        self.emit = emit
    }

    func consume(_ snapshot: NowPlayingSnapshot) {
        guard let title = normalized(snapshot.title),
              let sourceBundleID = normalized(snapshot.sourceBundleID)
        else {
            closeAll(with: snapshot, reason: "NO_ACTIVE_MEDIA")
            previousSnapshot = snapshot
            return
        }

        if currentSession == nil {
            startSession(
                title: title,
                sourceBundleID: sourceBundleID,
                durationTotal: snapshot.duration,
                at: snapshot
            )
            previousSnapshot = snapshot
            return
        }

        if isSessionSwitch(title: title, sourceBundleID: sourceBundleID) {
            closeAll(with: snapshot, reason: "SESSION_SWITCH")
            startSession(
                title: title,
                sourceBundleID: sourceBundleID,
                durationTotal: snapshot.duration,
                at: snapshot
            )
            previousSnapshot = snapshot
            return
        }

        handlePlaybackTransitions(snapshot)
        previousSnapshot = snapshot
    }

    private func startSession(
        title: String,
        sourceBundleID: String,
        durationTotal: Double?,
        at snapshot: NowPlayingSnapshot
    ) {
        let session = Session(
            id: UUID(),
            title: title,
            sourceBundleID: sourceBundleID,
            startedAt: snapshot.timestamp,
            durationTotal: durationTotal
        )
        currentSession = session
        observedMinElapsed = snapshot.elapsedTime
        observedMaxElapsed = snapshot.elapsedTime

        print("START SESSION id=\(session.id.uuidString) title=\(title) sourceBundleID=\(sourceBundleID)")
        emit(.sessionStarted(
            id: session.id,
            title: title,
            sourceBundleID: sourceBundleID,
            startedAt: snapshot.timestamp,
            durationTotal: durationTotal
        ))

        if isPlaying(snapshot), let elapsed = snapshot.elapsedTime {
            openSegmentStartSec = elapsed
            openSegmentStartedAt = snapshot.timestamp
            print("SEGMENT START at=\(elapsed)")
            emit(.segmentStarted(sessionID: session.id, startedAt: snapshot.timestamp))
        }
    }

    private func handlePlaybackTransitions(_ snapshot: NowPlayingSnapshot) {
        let prev = previousSnapshot
        let prevRate = prev?.playbackRate ?? 0
        let currRate = snapshot.playbackRate ?? 0
        observeElapsed(snapshot.elapsedTime)

        if openSegmentStartSec == nil, currRate > 0, let elapsed = snapshot.elapsedTime {
            openSegmentStartSec = elapsed
            openSegmentStartedAt = snapshot.timestamp
            print("SEGMENT START at=\(elapsed)")
            if let session = currentSession {
                emit(.segmentStarted(sessionID: session.id, startedAt: snapshot.timestamp))
            }
        }

        if let start = openSegmentStartSec {
            if currRate <= 0 {
                staleWhilePlayingCount = 0
                let end = bestEndElapsed(previous: prev, current: snapshot, fallback: start)
                closeSegment(from: start, to: end, reason: "PAUSE_OR_STOP", endedAt: snapshot.timestamp)
                return
            }

            if didElapsedProgress(previous: prev, current: snapshot) {
                staleWhilePlayingCount = 0
            } else if currRate > 0 {
                staleWhilePlayingCount += 1
                if staleWhilePlayingCount >= staleWhilePlayingLimit {
                    let end = bestEndElapsed(previous: prev, current: snapshot, fallback: start)
                    closeSegment(from: start, to: end, reason: "STALE_PROGRESS", endedAt: snapshot.timestamp)
                    staleWhilePlayingCount = 0
                    return
                }
            }

            if isSeekDetected(previous: prev, current: snapshot, prevRate: prevRate, currRate: currRate) {
                let end = bestEndElapsed(previous: prev, current: snapshot, fallback: start)
                closeSegment(from: start, to: end, reason: "SEEK", endedAt: snapshot.timestamp)

                if let prevElapsed = prev?.elapsedTime, let currElapsed = snapshot.elapsedTime {
                    print("SEEK DETECTED from=\(prevElapsed) to=\(currElapsed)")
                }

                if let newStart = snapshot.elapsedTime, isPlaying(snapshot) {
                    openSegmentStartSec = newStart
                    openSegmentStartedAt = snapshot.timestamp
                    print("SEGMENT START at=\(newStart)")
                    if let session = currentSession {
                        emit(.segmentStarted(sessionID: session.id, startedAt: snapshot.timestamp))
                    }
                }
            }
        }
    }

    private func closeAll(with snapshot: NowPlayingSnapshot, reason: String) {
        if let start = openSegmentStartSec {
            let end = bestEndElapsed(previous: previousSnapshot, current: snapshot, fallback: start)
            closeSegment(from: start, to: end, reason: reason, endedAt: snapshot.timestamp)
        } else if let session = currentSession,
                  let minElapsed = observedMinElapsed,
                  let maxElapsed = observedMaxElapsed,
                  (maxElapsed - minElapsed) >= 0.25 {
            print("SEGMENT END start=\(minElapsed) end=\(maxElapsed) reason=\(reason)_SYNTHETIC")
            let duration = maxElapsed - minElapsed
            let startedAt = Date(timeInterval: -duration, since: Date())
            emit(.segmentEnded(
                sessionID: session.id,
                startSec: minElapsed,
                endSec: maxElapsed,
                startedAt: startedAt,
                endedAt: Date(),
                reason: "\(reason)_SYNTHETIC"
            ))
        }

        if let session = currentSession {
            let duration = snapshot.timestamp.timeIntervalSince(session.startedAt)
            print("END SESSION id=\(session.id.uuidString) title=\(session.title) sourceBundleID=\(session.sourceBundleID) wallTimeSec=\(duration)")
            emit(.sessionEnded(id: session.id, endedAt: snapshot.timestamp))
        }

        openSegmentStartSec = nil
        openSegmentStartedAt = nil
        currentSession = nil
        staleWhilePlayingCount = 0
        observedMinElapsed = nil
        observedMaxElapsed = nil
    }

    private func closeSegment(from start: Double, to end: Double, reason: String, endedAt: Date) {
        var safeEnd = max(end, start)

        if let wallStart = openSegmentStartedAt {
            let wallBasedEnd = start + max(0, endedAt.timeIntervalSince(wallStart))
            if safeEnd - start < 0.10 {
                safeEnd = max(safeEnd, wallBasedEnd)
            }
        }

        print("SEGMENT END start=\(start) end=\(safeEnd) reason=\(reason)")

        if let session = currentSession {
            let duration = safeEnd - start
            let startedAt = Date(timeInterval: -duration, since: endedAt)
            emit(.segmentEnded(
                sessionID: session.id,
                startSec: start,
                endSec: safeEnd,
                startedAt: startedAt,
                endedAt: endedAt,
                reason: reason
            ))
        }

        openSegmentStartSec = nil
        openSegmentStartedAt = nil
    }

    private func bestEndElapsed(previous: NowPlayingSnapshot?, current: NowPlayingSnapshot, fallback: Double) -> Double {
        let prevElapsed = previous?.elapsedTime
        let currElapsed = current.elapsedTime

        switch (prevElapsed, currElapsed) {
        case let (p?, c?):
            return max(p, c)
        case let (p?, nil):
            return p
        case let (nil, c?):
            return c
        default:
            return fallback
        }
    }

    private func observeElapsed(_ value: Double?) {
        guard let value else { return }
        if let currentMin = observedMinElapsed {
            observedMinElapsed = Swift.min(currentMin, value)
        } else {
            observedMinElapsed = value
        }

        if let currentMax = observedMaxElapsed {
            observedMaxElapsed = Swift.max(currentMax, value)
        } else {
            observedMaxElapsed = value
        }
    }

    private func isSessionSwitch(title: String, sourceBundleID: String) -> Bool {
        guard let session = currentSession else { return false }
        return session.title != title || session.sourceBundleID != sourceBundleID
    }

    private func didElapsedProgress(previous: NowPlayingSnapshot?, current: NowPlayingSnapshot) -> Bool {
        guard let p = previous?.elapsedTime, let c = current.elapsedTime else { return false }
        return c > p + 0.1
    }

    private func isSeekDetected(
        previous: NowPlayingSnapshot?,
        current: NowPlayingSnapshot,
        prevRate: Double,
        currRate: Double
    ) -> Bool {
        guard let prevElapsed = previous?.elapsedTime,
              let currElapsed = current.elapsedTime,
              prevRate > 0,
              currRate > 0
        else {
            return false
        }

        let delta = currElapsed - prevElapsed

        if delta < -backwardSeekThreshold {
            return true
        }

        let expectedForward = pollInterval * max(prevRate, currRate)
        if delta > expectedForward + forwardSeekThreshold {
            return true
        }

        return false
    }

    private func isPlaying(_ snapshot: NowPlayingSnapshot) -> Bool {
        (snapshot.playbackRate ?? 0) > 0
    }

    private func normalized(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
