import SwiftUI

// PROTOTYPE mock data — same shape as prototypes/issue-23-menubar-popover's
// MockData.swift (which mirrors prototypes/menubar-layout/index.html's
// `DAILY`) so all three prototypes stay comparable on the same fictional
// August 2026 dataset. "Today" = Aug 29.

enum Service: String, CaseIterable, Identifiable {
    case youtube, netflix, twitch, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .youtube: "YouTube"
        case .netflix: "Netflix"
        case .twitch: "Twitch"
        case .other: "Other sites"
        }
    }

    var symbol: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .netflix: "tv.fill"
        case .twitch: "gamecontroller.fill"
        case .other: "globe"
        }
    }

    // Viz palette departs from brand so stacked bars/charts stay legible
    // (YouTube and Netflix are both red in reality). Kept identical to the
    // other prototypes' hexes so the data-viz meaning doesn't drift between
    // versions — only the chrome around it changes.
    var color: Color {
        switch self {
        case .youtube: Color(red: 0.898, green: 0.204, blue: 0.169) // #e5342b
        case .netflix: Color(red: 0.878, green: 0.565, blue: 0.184) // #e0902f
        case .twitch: Color(red: 0.478, green: 0.361, blue: 1.0) // #7a5cff
        case .other: Color(red: 0.604, green: 0.631, blue: 0.678) // #9aa1ad
        }
    }
}

enum RangePreset: String, CaseIterable, Identifiable {
    case today, week, month, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .month: "This Month"
        case .custom: "Custom"
        }
    }
}

// NOTE: `Pane` lives in SwitcherVariants.swift in this prototype — it's the
// thing under test here, so it carries extra affordances (short labels) the
// other prototypes don't need.

typealias DayMinutes = [Service: Int]

enum MockData {
    static let today = 29 // day-of-month, August 2026

    static let daily: [Int: DayMinutes] = [
        4: [.youtube: 55, .netflix: 20],
        5: [.twitch: 90],
        8: [.youtube: 35, .other: 15],
        9: [.netflix: 120],
        12: [.youtube: 40],
        13: [.netflix: 95],
        18: [.youtube: 30, .twitch: 20],
        19: [.netflix: 60, .other: 15],
        20: [.youtube: 55],
        22: [.twitch: 110],
        25: [.youtube: 182, .netflix: 166, .other: 40],
        26: [:],
        27: [.twitch: 72],
        28: [.youtube: 95, .netflix: 90, .other: 27],
        29: [.youtube: 100, .netflix: 25],
    ]

    // Fictional weekday letters for the collapsed week row (Aug 25 = "Monday").
    static let weekdayLetter: [Int: String] = [
        25: "M", 26: "T", 27: "W", 28: "T", 29: "F", 30: "S", 31: "S",
    ]
    static let weekdayName: [Int: String] = [
        25: "Mon", 26: "Tue", 27: "Wed", 28: "Thu", 29: "Fri", 30: "Sat", 31: "Sun",
    ]

    static func rangeDays(_ preset: RangePreset, customStart: Int?, customEnd: Int?) -> ClosedRange<Int>? {
        switch preset {
        case .today: return today...today
        case .week: return 25...29
        case .month: return 1...today
        case .custom:
            guard let start = customStart else { return nil }
            let end = customEnd ?? start
            return min(start, end)...max(start, end)
        }
    }

    static func dayTotal(_ day: Int) -> Int {
        (daily[day] ?? [:]).values.reduce(0, +)
    }

    static func serviceTotals(over range: ClosedRange<Int>) -> DayMinutes {
        var totals: DayMinutes = [.youtube: 0, .netflix: 0, .twitch: 0, .other: 0]
        for day in range {
            guard let minutes = daily[day] else { continue }
            for (service, mins) in minutes { totals[service, default: 0] += mins }
        }
        return totals
    }

    static func grandTotal(over range: ClosedRange<Int>) -> Int {
        serviceTotals(over: range).values.reduce(0, +)
    }

    static func rangeResolvedLabel(_ range: ClosedRange<Int>?) -> String {
        guard let range else { return "pick days" }
        let fmt: (Int) -> String = { "Aug \($0)" }
        return range.lowerBound == range.upperBound
            ? fmt(range.lowerBound)
            : "\(fmt(range.lowerBound)) – \(fmt(range.upperBound))"
    }

    static func formatMinutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    // YouTube's contentFormat split, and its embedded sub-line — same fixed
    // shares the other prototypes use.
    static let youtubeSplit: [(label: String, frac: Double)] = [
        ("standard", 0.66), ("short", 0.28), ("live", 0.06),
    ]
    static let youtubeEmbeddedFrac = 0.05

    static let needsAdapter: [(name: String, share: Double, note: String)] = [
        ("typo.blog", 0.60, "generic extraction · title only, no video id"),
        ("ocw.mit.edu", 0.40, "generic extraction · no author"),
    ]
}

struct MockView: Identifiable {
    let id = UUID()
    let service: Service
    let title: String
    let author: String
    let format: String // "standard" | "short" | "live"
    let embedded: Bool
    let watched: String
    let coverage: Double? // nil = live / unknown length
    let at: String
}

struct MockHistoryDay: Identifiable {
    let id: String
    let dayOfMonth: Int
    let name: String
    let date: String?
    let span: String
    let pastMidnight: Bool
    let views: [MockView]
}

extension MockData {
    static let history: [MockHistoryDay] = [
        MockHistoryDay(
            id: "today", dayOfMonth: 29, name: "Today", date: nil,
            span: "started 6:12 PM · still open", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "The Untold History of the Spreadsheet", author: "Veritasium", format: "standard", embedded: false, watched: "48m", coverage: 0.72, at: "7:20 PM"),
                MockView(service: .youtube, title: "lofi hip hop radio — beats to relax/study to", author: "Lofi Girl", format: "live", embedded: false, watched: "52m", coverage: nil, at: "8:30 PM"),
                MockView(service: .netflix, title: "The Diplomat — S2:E4 \u{201C}Keep Your Enemies Closer\u{201D}", author: "Netflix", format: "standard", embedded: false, watched: "25m", coverage: 0.40, at: "9:14 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-thu", dayOfMonth: 28, name: "Thursday", date: "Aug 28",
            span: "7:02 PM → 11:48 PM", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "How the ILC-2 landed 6 boosters in one night", author: "Scott Manley", format: "standard", embedded: false, watched: "1h 04m", coverage: 0.98, at: "7:02 PM"),
                MockView(service: .youtube, title: "#Shorts — the one-pan trick", author: "Adam Ragusea", format: "short", embedded: false, watched: "3m", coverage: 1.0, at: "8:11 PM"),
                MockView(service: .other, title: "Type design lecture 04 (embedded on typo.blog)", author: "typo.blog", format: "standard", embedded: true, watched: "27m", coverage: 0.35, at: "8:30 PM"),
                MockView(service: .netflix, title: "Killing Eve — S1:E1", author: "Netflix", format: "standard", embedded: false, watched: "1h 30m", coverage: 1.0, at: "9:40 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-wed", dayOfMonth: 27, name: "Wednesday", date: "Aug 27",
            span: "9:40 PM → 10:52 PM", pastMidnight: false,
            views: [
                MockView(service: .twitch, title: "summit1g — just chatting / DayZ", author: "summit1g", format: "live", embedded: false, watched: "1h 12m", coverage: nil, at: "9:40 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-mon", dayOfMonth: 25, name: "Monday", date: "Aug 25",
            span: "9:04 AM → 3:12 AM (+1d)", pastMidnight: true,
            views: [
                MockView(service: .youtube, title: "Deep work playlist (background while coding)", author: "various", format: "standard", embedded: false, watched: "2h 22m", coverage: 0.9, at: "9:04 AM"),
                MockView(service: .netflix, title: "Dune: Part Two", author: "Netflix", format: "standard", embedded: false, watched: "2h 46m", coverage: 1.0, at: "11:20 PM"),
                MockView(service: .other, title: "MIT 6.006 lecture 3 (ocw.mit.edu)", author: "ocw.mit.edu", format: "standard", embedded: false, watched: "40m", coverage: 0.5, at: "1:40 AM (Tue clock)"),
            ]
        ),
    ]
}

struct MockSettings {
    var pairingToken = "wl_9f2a17b4…c71d"
    var port = 47600
    var retentionDays = 90
    var launchAtLogin = true
    var dayEndsAround = "04:00"
    var version = "0.1.0 · contract v1"
}
