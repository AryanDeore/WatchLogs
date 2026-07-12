//
//  TrackingStore.swift
//  WatchLogs
//
//  Created by Pi on 7/11/26.
//

import Foundation

final class TrackingStore {
    private let db = DatabaseManager.shared
    private let liveState = LivePlaybackState.shared

    func handle(_ event: TrackerEvent) {
        Task { @MainActor in
            liveState.handle(event)
        }

        switch event {
        case let .sessionStarted(id, title, sourceBundleID, startedAt, durationTotal):
            db.startSession(
                id: id,
                title: title,
                bundleID: sourceBundleID,
                startedAt: startedAt,
                durationTotal: durationTotal
            )

        case let .segmentStarted(_, _):
            break

        case let .segmentEnded(sessionID, startSec, endSec, _, _, _):
            db.addSegment(sessionID: sessionID, startSec: startSec, endSec: endSec)

        case let .sessionEnded(id, endedAt):
            db.endSession(sessionID: id, endedAt: endedAt)
        }
    }
}
