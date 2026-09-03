import AppKit
import SwiftUI

/// Sim state shared by the live status item and the gallery. Watched time is
/// derived from the wall clock (an anchor date + accumulated seconds), so any
/// number of timer-driven views can read it without ever double-counting.
@Observable
@MainActor
final class PrototypeModel {
    static let shared = PrototypeModel()

    var selectedVariant: IconTimeVariant = .inlineTrailing
    var goalHours: Double = 3
    /// Sim seconds of watched time per real second, so the readout visibly moves.
    var speed: Double = 60

    private var accumulated: TimeInterval = 65 * 60  // start at 1:05
    private var anchor: Date?

    var isCounting: Bool { anchor != nil }

    func watchedSeconds(at now: Date = .now) -> Int {
        var s = accumulated
        if let anchor { s += now.timeIntervalSince(anchor) * speed }
        return max(0, Int(s))
    }

    func setWatched(minutes: Double) {
        accumulated = max(0, minutes) * 60
        if anchor != nil { anchor = .now }
    }

    // Bindings for the gallery controls.
    var watchedMinutes: Double {
        get { Double(watchedSeconds()) / 60 }
        set { setWatched(minutes: newValue) }
    }

    var counting: Bool {
        get { isCounting }
        set {
            if newValue, anchor == nil {
                anchor = .now
            } else if !newValue, let a = anchor {
                accumulated += Date.now.timeIntervalSince(a) * speed
                anchor = nil
            }
        }
    }

}
