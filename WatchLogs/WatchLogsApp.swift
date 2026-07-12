//
//  WatchLogsApp.swift
//  WatchLogs
//
//  Created by Aryan Deore on 7/5/26.
//

import SwiftUI

@main
struct WatchLogsApp: App {
    private let probe = NowPlayingProbe()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    probe.start()
                }
        }
    }
}
