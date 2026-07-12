//
//  ContentView.swift
//  WatchLogs
//
//  Created by Aryan Deore on 7/5/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                Text(vm.formattedTodayTotal())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            Divider()

            Text("Recent Sessions")
                .font(.headline)

            if vm.recentSessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            } else {
                List(vm.recentSessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.body)
                            .lineLimit(2)

                        HStack {
                            Text(session.bundleID)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(vm.displayDuration(for: session))
                                .monospacedDigit()
                        }
                        .font(.caption)

                        Text(vm.formattedTime(session.startedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .onAppear {
            vm.refresh()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            vm.refresh()
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

#Preview {
    ContentView()
}
