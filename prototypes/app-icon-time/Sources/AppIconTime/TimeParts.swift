import Foundation

/// The user asked for the readout in "(MM, HH:MM)" form: under an hour show
/// bare minutes, at/over an hour switch to H:MM. `compact` is that rule.
/// `clockString` is the always-colon form some variants need (so there is a
/// colon to blink, or a separator to swap the mark in for).
struct TimeParts {
    let totalMinutes: Int
    let underHour: Bool
    let h: Int
    let m: Int
    let compact: String
    let clockString: String
    let mm: String

    init(seconds: Int) {
        let mins = max(0, seconds) / 60
        totalMinutes = mins
        underHour = mins < 60
        h = mins / 60
        m = mins % 60
        mm = String(format: "%02d", m)
        compact = underHour ? "\(mins)m" : "\(h):\(String(format: "%02d", m))"
        clockString = underHour
            ? "0:\(String(format: "%02d", mins))"
            : "\(h):\(String(format: "%02d", m))"
    }
}
