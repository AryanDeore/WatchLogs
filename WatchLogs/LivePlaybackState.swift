//
//  LivePlaybackState.swift
//  WatchLogs
//
//  Created by Pi on 7/11/26.
//

import Foundation

@MainActor
final class LivePlaybackState {
    static let shared = LivePlaybackState()

    private(set) var activeSessionID: UUID?
    private(set) var activeSegmentStartedAt: Date?

    private init() {}

    func handle(_ event: TrackerEvent) {
        switch event {
        case let .sessionStarted(id, _, _, startedAt, _):
            activeSessionID = id
            activeSegmentStartedAt = nil
            if startedAt > Date() { activeSegmentStartedAt = nil }

        case let .segmentStarted(sessionID, startedAt):
            activeSessionID = sessionID
            activeSegmentStartedAt = startedAt

        case let .segmentEnded(sessionID, _, _, _, _, _):
            if activeSessionID == sessionID {
                activeSegmentStartedAt = nil
            }

        case let .sessionEnded(id, _):
            if activeSessionID == id {
                activeSessionID = nil
                activeSegmentStartedAt = nil
            }
        }
    }

    func inProgressSeconds(for sessionID: String, now: Date = Date()) -> Double {
        guard let activeSessionID,
              activeSessionID.uuidString == sessionID,
              let start = activeSegmentStartedAt
        else {
            return 0
        }

        return max(0, now.timeIntervalSince(start))
    }

    func totalInProgressSeconds(now: Date = Date()) -> Double {
        guard let start = activeSegmentStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }
}
