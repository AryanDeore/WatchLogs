//
//  TrackerEvents.swift
//  WatchLogs
//
//  Created by Pi on 7/11/26.
//

import Foundation

enum TrackerEvent {
    case sessionStarted(id: UUID, title: String, sourceBundleID: String, startedAt: Date, durationTotal: Double?)
    case segmentStarted(sessionID: UUID, startedAt: Date)
    case segmentEnded(sessionID: UUID, startSec: Double, endSec: Double, startedAt: Date, endedAt: Date, reason: String)
    case sessionEnded(id: UUID, endedAt: Date)
}
