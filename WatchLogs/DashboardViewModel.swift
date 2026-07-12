//
//  DashboardViewModel.swift
//  WatchLogs
//
//  Created by Pi on 7/11/26.
//

import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var todayTotalSeconds: Double = 0
    @Published var recentSessions: [RecentSessionSummary] = []

    private let db = DatabaseManager.shared
    private let liveState = LivePlaybackState.shared

    func refresh() {
        let persisted = db.todayTotalSeconds()
        let inProgress = liveState.totalInProgressSeconds()
        todayTotalSeconds = persisted + inProgress
        recentSessions = db.recentSessions(limit: 20)
    }

    func formattedTodayTotal() -> String {
        let total = Int(todayTotalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    func displayDuration(for session: RecentSessionSummary) -> String {
        let live = liveState.inProgressSeconds(for: session.id)
        return formattedDuration(session.durationSec + live)
    }

    func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
