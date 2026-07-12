//
//  NowPlayingSnapshot.swift
//  WatchLogs
//
//  Created by Aryan Deore on 7/11/26.
//

import Foundation

struct NowPlayingSnapshot {
    let timestamp: Date
    let title: String?
    let elapsedTime: Double?
    let duration: Double?
    let playbackRate: Double?
    let sourceBundleID: String?
    let frontmostBundleID: String?
}
