import SwiftUI

// PROTOTYPE mock data — same shape as prototypes/issue-23-menubar-popover's
// MockData.swift (which mirrors prototypes/menubar-layout/index.html's
// `DAILY`) so all three prototypes stay comparable on the same fictional
// dataset. Covers June 1 – Aug 29, 2026, the past 3 months. "Today" = Aug 29, 2026.

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

enum Pane: String, CaseIterable, Identifiable {
    case history, byService, trends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .history: "History"
        case .byService: "Services"
        case .trends: "Trends"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        case .byService: "chart.pie"
        case .trends: "chart.bar.xaxis"
        }
    }
}

typealias DayMinutes = [Service: Int]

// A calendar date, month-and-year aware. `daily`'s old keying (day-of-month
// only, 1-31) couldn't tell June 15 from August 15 — it silently assumed a
// single month. This is a plain value type instead of Foundation's Date so
// dictionary literals stay readable and equality doesn't depend on timezone.
struct MockDate: Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    static func < (lhs: MockDate, rhs: MockDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    func adding(days delta: Int) -> MockDate {
        let next = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date
        let c = Calendar.current.dateComponents([.year, .month, .day], from: next)
        return MockDate(year: c.year!, month: c.month!, day: c.day!)
    }

    // 0 = Monday … 6 = Sunday, matching CalendarBox's month-grid leading-blank math.
    var isoWeekdayMondayFirst: Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    var weekdayLetter: String {
        ["M", "T", "W", "T", "F", "S", "S"][isoWeekdayMondayFirst]
    }

    var weekdayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    var monthAbbrev: String {
        let f = DateFormatter()
        f.dateFormat = "LLL"
        return f.string(from: date)
    }

    var description: String { "\(monthAbbrev) \(day)" }
}

extension ClosedRange where Bound == MockDate {
    // MockDate isn't Strideable, so `ClosedRange<MockDate>` doesn't get the
    // free `Array.init` a `ClosedRange<Int>` would — this walks it by hand.
    var days: [MockDate] {
        var result: [MockDate] = []
        var day = lowerBound
        while day <= upperBound {
            result.append(day)
            day = day.adding(days: 1)
        }
        return result
    }
}

enum MockData {
    static let today = MockDate(year: 2026, month: 8, day: 29)

    static let daily: [MockDate: DayMinutes] = [
        // June 2026
        MockDate(year: 2026, month: 6, day: 1): [.youtube: 50, .netflix: 55],
        MockDate(year: 2026, month: 6, day: 3): [.youtube: 18, .netflix: 79, .other: 22],
        MockDate(year: 2026, month: 6, day: 4): [.youtube: 68, .netflix: 170],
        MockDate(year: 2026, month: 6, day: 6): [.youtube: 50, .netflix: 106, .twitch: 78, .other: 32],
        MockDate(year: 2026, month: 6, day: 7): [.youtube: 63],
        MockDate(year: 2026, month: 6, day: 8): [.youtube: 95],
        MockDate(year: 2026, month: 6, day: 9): [.youtube: 44],
        MockDate(year: 2026, month: 6, day: 11): [.youtube: 121, .netflix: 114],
        MockDate(year: 2026, month: 6, day: 12): [.youtube: 24, .twitch: 123],
        MockDate(year: 2026, month: 6, day: 13): [.youtube: 133],
        MockDate(year: 2026, month: 6, day: 16): [.youtube: 55, .twitch: 146],
        MockDate(year: 2026, month: 6, day: 18): [.youtube: 65, .other: 18],
        MockDate(year: 2026, month: 6, day: 19): [.youtube: 48],
        MockDate(year: 2026, month: 6, day: 20): [.netflix: 146, .twitch: 36],
        MockDate(year: 2026, month: 6, day: 21): [.youtube: 102, .twitch: 78],
        MockDate(year: 2026, month: 6, day: 22): [.youtube: 85, .twitch: 122, .other: 44],
        MockDate(year: 2026, month: 6, day: 25): [.youtube: 35],
        MockDate(year: 2026, month: 6, day: 26): [.youtube: 37, .twitch: 110],
        MockDate(year: 2026, month: 6, day: 27): [.youtube: 34, .netflix: 61],
        MockDate(year: 2026, month: 6, day: 28): [.youtube: 56, .twitch: 76],
        MockDate(year: 2026, month: 6, day: 30): [.youtube: 127, .twitch: 123],
        // July 2026
        MockDate(year: 2026, month: 7, day: 1): [.twitch: 90],
        MockDate(year: 2026, month: 7, day: 2): [.youtube: 92, .twitch: 99],
        MockDate(year: 2026, month: 7, day: 3): [.youtube: 66],
        MockDate(year: 2026, month: 7, day: 4): [.youtube: 43, .netflix: 25],
        MockDate(year: 2026, month: 7, day: 5): [.youtube: 95, .netflix: 37],
        MockDate(year: 2026, month: 7, day: 6): [.youtube: 100],
        MockDate(year: 2026, month: 7, day: 8): [.youtube: 75, .twitch: 42],
        MockDate(year: 2026, month: 7, day: 9): [.youtube: 125],
        MockDate(year: 2026, month: 7, day: 10): [.youtube: 58, .twitch: 54],
        MockDate(year: 2026, month: 7, day: 11): [.youtube: 50, .other: 45],
        MockDate(year: 2026, month: 7, day: 12): [.youtube: 84],
        MockDate(year: 2026, month: 7, day: 14): [.youtube: 42, .other: 10],
        MockDate(year: 2026, month: 7, day: 16): [.youtube: 86],
        MockDate(year: 2026, month: 7, day: 17): [.youtube: 39, .netflix: 34],
        MockDate(year: 2026, month: 7, day: 19): [.youtube: 79, .other: 42],
        MockDate(year: 2026, month: 7, day: 20): [.youtube: 91, .netflix: 80],
        MockDate(year: 2026, month: 7, day: 21): [.youtube: 20],
        MockDate(year: 2026, month: 7, day: 22): [.netflix: 100],
        MockDate(year: 2026, month: 7, day: 23): [.youtube: 55, .other: 49],
        MockDate(year: 2026, month: 7, day: 26): [.youtube: 48, .netflix: 109],
        MockDate(year: 2026, month: 7, day: 27): [.youtube: 121],
        MockDate(year: 2026, month: 7, day: 29): [.youtube: 85, .netflix: 46, .other: 17],
        // August 2026
        MockDate(year: 2026, month: 8, day: 1): [.youtube: 41, .twitch: 111],
        MockDate(year: 2026, month: 8, day: 2): [.youtube: 131, .twitch: 84],
        MockDate(year: 2026, month: 8, day: 3): [.youtube: 31],
        MockDate(year: 2026, month: 8, day: 4): [.youtube: 55, .netflix: 20],
        MockDate(year: 2026, month: 8, day: 5): [.twitch: 90],
        MockDate(year: 2026, month: 8, day: 6): [.youtube: 16, .netflix: 58],
        MockDate(year: 2026, month: 8, day: 7): [.youtube: 31, .netflix: 113],
        MockDate(year: 2026, month: 8, day: 8): [.youtube: 35, .other: 15],
        MockDate(year: 2026, month: 8, day: 9): [.netflix: 120],
        MockDate(year: 2026, month: 8, day: 12): [.youtube: 40],
        MockDate(year: 2026, month: 8, day: 13): [.netflix: 95],
        MockDate(year: 2026, month: 8, day: 14): [.youtube: 28, .netflix: 163],
        MockDate(year: 2026, month: 8, day: 15): [.youtube: 224], // 10 videos + 12 shorts — see `history`
        MockDate(year: 2026, month: 8, day: 16): [.youtube: 134, .netflix: 61],
        MockDate(year: 2026, month: 8, day: 18): [.youtube: 30, .twitch: 20],
        MockDate(year: 2026, month: 8, day: 19): [.netflix: 60, .other: 15],
        MockDate(year: 2026, month: 8, day: 20): [.youtube: 55],
        MockDate(year: 2026, month: 8, day: 21): [.netflix: 125],
        MockDate(year: 2026, month: 8, day: 22): [.twitch: 110],
        MockDate(year: 2026, month: 8, day: 24): [.netflix: 29],
        MockDate(year: 2026, month: 8, day: 25): [.youtube: 182, .netflix: 166, .other: 40],
        MockDate(year: 2026, month: 8, day: 26): [:],
        MockDate(year: 2026, month: 8, day: 27): [.twitch: 72],
        MockDate(year: 2026, month: 8, day: 28): [.youtube: 95, .netflix: 90, .other: 27],
        MockDate(year: 2026, month: 8, day: 29): [.youtube: 100, .netflix: 25],
    ]

    static func rangeDays(_ preset: RangePreset, customStart: MockDate?, customEnd: MockDate?) -> ClosedRange<MockDate>? {
        switch preset {
        case .today: return today...today
        case .week: return today.adding(days: -today.isoWeekdayMondayFirst)...today
        case .month: return MockDate(year: today.year, month: today.month, day: 1)...today
        case .custom:
            guard let start = customStart else { return nil }
            let end = customEnd ?? start
            return min(start, end)...max(start, end)
        }
    }

    static func dayTotal(_ day: MockDate) -> Int {
        (daily[day] ?? [:]).values.reduce(0, +)
    }

    static func serviceTotals(over range: ClosedRange<MockDate>) -> DayMinutes {
        var totals: DayMinutes = [.youtube: 0, .netflix: 0, .twitch: 0, .other: 0]
        var day = range.lowerBound
        while day <= range.upperBound {
            if let minutes = daily[day] {
                for (service, mins) in minutes { totals[service, default: 0] += mins }
            }
            day = day.adding(days: 1)
        }
        return totals
    }

    static func grandTotal(over range: ClosedRange<MockDate>) -> Int {
        serviceTotals(over: range).values.reduce(0, +)
    }

    static func rangeResolvedLabel(_ range: ClosedRange<MockDate>?) -> String {
        guard let range else { return "pick days" }
        return range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound) – \(range.upperBound)"
    }

    static func formatMinutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    // YouTube's contentFormat split, and its embedded sub-line — same fixed
    // shares the other prototypes use.
    static let youtubeSplit: [(format: ContentFormat, frac: Double)] = [
        (.video, 0.66), (.short, 0.28), (.live, 0.06),
    ]

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
    let date: MockDate
    let name: String
    let dateLabel: String?
    let span: String
    let pastMidnight: Bool
    let views: [MockView]
}

extension MockData {
    static let history: [MockHistoryDay] = [
        MockHistoryDay(
            id: "today", date: MockDate(year: 2026, month: 8, day: 29), name: "Today", dateLabel: nil,
            span: "started 6:12 PM", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "The Untold History of the Spreadsheet", author: "Veritasium", format: "standard", embedded: false, watched: "48m", coverage: 0.72, at: "7:20 PM"),
                MockView(service: .youtube, title: "lofi hip hop radio — beats to relax/study to", author: "Lofi Girl", format: "live", embedded: false, watched: "52m", coverage: nil, at: "8:30 PM"),
                MockView(service: .netflix, title: "The Diplomat — S2:E4 \u{201C}Keep Your Enemies Closer\u{201D}", author: "Netflix", format: "standard", embedded: false, watched: "25m", coverage: 0.40, at: "9:14 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-thu", date: MockDate(year: 2026, month: 8, day: 28), name: "Thursday", dateLabel: "Aug 28",
            span: "7:02 PM → 11:48 PM", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "How the ILC-2 landed 6 boosters in one night", author: "Scott Manley", format: "standard", embedded: false, watched: "1h 04m", coverage: 0.98, at: "7:02 PM"),
                MockView(service: .youtube, title: "#Shorts — the one-pan trick", author: "Adam Ragusea", format: "short", embedded: false, watched: "3m", coverage: 1.0, at: "8:11 PM"),
                MockView(service: .other, title: "Type design lecture 04 (embedded on typo.blog)", author: "typo.blog", format: "standard", embedded: true, watched: "27m", coverage: 0.35, at: "8:30 PM"),
                MockView(service: .netflix, title: "Killing Eve — S1:E1", author: "Netflix", format: "standard", embedded: false, watched: "1h 30m", coverage: 1.0, at: "9:40 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-wed", date: MockDate(year: 2026, month: 8, day: 27), name: "Wednesday", dateLabel: "Aug 27",
            span: "9:40 PM → 10:52 PM", pastMidnight: false,
            views: [
                MockView(service: .twitch, title: "summit1g — just chatting / DayZ", author: "summit1g", format: "live", embedded: false, watched: "1h 12m", coverage: nil, at: "9:40 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-mon", date: MockDate(year: 2026, month: 8, day: 25), name: "Monday", dateLabel: "Aug 25",
            span: "9:04 AM → 3:12 AM (+1d)", pastMidnight: true,
            views: [
                MockView(service: .youtube, title: "Deep work playlist (background while coding)", author: "various", format: "standard", embedded: false, watched: "2h 22m", coverage: 0.9, at: "9:04 AM"),
                MockView(service: .netflix, title: "Dune: Part Two", author: "Netflix", format: "standard", embedded: false, watched: "2h 46m", coverage: 1.0, at: "11:20 PM"),
                MockView(service: .other, title: "MIT 6.006 lecture 3 (ocw.mit.edu)", author: "ocw.mit.edu", format: "standard", embedded: false, watched: "40m", coverage: 0.5, at: "1:40 AM (Tue clock)"),
            ]
        ),
        // Aug 15 — the heaviest YouTube day in the dataset: 10 full videos plus
        // a 12-clip Shorts binge, deliberately dense to exercise the History
        // pane and the youtubeSplit breakdown at a higher view count than any
        // other day here.
        MockHistoryDay(
            id: "d-aug15", date: MockDate(year: 2026, month: 8, day: 15), name: "Saturday", dateLabel: "Aug 15",
            span: "9:12 AM → 11:02 PM", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "This one trick fixed my sourdough", author: "Adam Ragusea", format: "short", embedded: false, watched: "52s", coverage: 1.0, at: "9:12 AM"),
                MockView(service: .youtube, title: "POV: you fix a 3am prod outage", author: "DevHumor", format: "short", embedded: false, watched: "41s", coverage: 1.0, at: "9:14 AM"),
                MockView(service: .youtube, title: "The Untold History of the Spreadsheet", author: "Veritasium", format: "standard", embedded: false, watched: "18m", coverage: 0.85, at: "9:20 AM"),
                MockView(service: .youtube, title: "How Compilers Actually Work", author: "Computerphile", format: "standard", embedded: false, watched: "19m", coverage: 1.0, at: "9:42 AM"),
                MockView(service: .youtube, title: "The smallest black hole ever found", author: "SciShow Shorts", format: "short", embedded: false, watched: "58s", coverage: 1.0, at: "11:05 AM"),
                MockView(service: .youtube, title: "Why cats always land on their feet", author: "Veritasium", format: "short", embedded: false, watched: "1m", coverage: 1.0, at: "11:07 AM"),
                MockView(service: .youtube, title: "This chess opening is illegal (not really)", author: "GothamChess", format: "short", embedded: false, watched: "47s", coverage: 1.0, at: "11:10 AM"),
                MockView(service: .youtube, title: "Why This Bridge Design Shouldn't Work", author: "Practical Engineering", format: "standard", embedded: false, watched: "15m", coverage: 0.9, at: "12:30 PM"),
                MockView(service: .youtube, title: "The Physics of Roller Coasters", author: "Real Engineering", format: "standard", embedded: false, watched: "16m", coverage: 1.0, at: "12:50 PM"),
                MockView(service: .youtube, title: "The $2 tool every home needs", author: "Home RenoVision", format: "short", embedded: false, watched: "39s", coverage: 1.0, at: "1:15 PM"),
                MockView(service: .youtube, title: "Rating gas station coffee", author: "James Hoffmann", format: "short", embedded: false, watched: "55s", coverage: 1.0, at: "1:17 PM"),
                MockView(service: .youtube, title: "Building a Mechanical Keyboard From Scratch", author: "Alec Steele", format: "standard", embedded: false, watched: "27m", coverage: 0.7, at: "3:40 PM"),
                MockView(service: .youtube, title: "I Tried the World's Hardest Sudoku", author: "Cracking the Cryptic", format: "standard", embedded: false, watched: "31m", coverage: 0.5, at: "4:20 PM"),
                MockView(service: .youtube, title: "How fast is the fastest keyboard?", author: "Alec Steele", format: "short", embedded: false, watched: "44s", coverage: 1.0, at: "5:05 PM"),
                MockView(service: .youtube, title: "One-line Python trick nobody tells you", author: "Corey Schafer", format: "short", embedded: false, watched: "1m", coverage: 1.0, at: "5:07 PM"),
                MockView(service: .youtube, title: "The Last Blacksmith in Town", author: "Kings of Pain", format: "standard", embedded: false, watched: "12m", coverage: 0.8, at: "6:45 PM"),
                MockView(service: .youtube, title: "Why Coffee Tastes Different at Altitude", author: "James Hoffmann", format: "standard", embedded: false, watched: "9m", coverage: 1.0, at: "7:10 PM"),
                MockView(service: .youtube, title: "Deep Work Playlist (Background While Coding)", author: "various", format: "standard", embedded: false, watched: "45m", coverage: 0.6, at: "8:00 PM"),
                MockView(service: .youtube, title: "The tiniest working steam engine", author: "This Old Tony", format: "short", embedded: false, watched: "50s", coverage: 1.0, at: "9:20 PM"),
                MockView(service: .youtube, title: "Why is this bridge sound so weird?", author: "Practical Engineering", format: "short", embedded: false, watched: "36s", coverage: 1.0, at: "9:22 PM"),
                MockView(service: .youtube, title: "Space station alarm sounds explained", author: "Scott Manley", format: "short", embedded: false, watched: "48s", coverage: 1.0, at: "9:24 PM"),
                MockView(service: .youtube, title: "How the ILC-2 landed 6 boosters in one night", author: "Scott Manley", format: "standard", embedded: false, watched: "22m", coverage: 1.0, at: "10:40 PM"),
            ]
        ),
        // A few spot-check days further back so a 3-month custom range has
        // more than one expandable entry to scroll through.
        MockHistoryDay(
            id: "d-jul22", date: MockDate(year: 2026, month: 7, day: 22), name: "Wednesday", dateLabel: "Jul 22",
            span: "8:10 PM → 9:55 PM", pastMidnight: false,
            views: [
                MockView(service: .netflix, title: "The Diplomat — S1:E6 \u{201C}The Optics of a Kidnapping\u{201D}", author: "Netflix", format: "standard", embedded: false, watched: "1h 45m", coverage: 1.0, at: "8:10 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-jul09", date: MockDate(year: 2026, month: 7, day: 9), name: "Thursday", dateLabel: "Jul 9",
            span: "6:40 PM → 8:50 PM", pastMidnight: false,
            views: [
                MockView(service: .youtube, title: "Restoring a rusted 1970s hand plane", author: "This Old Tony", format: "standard", embedded: false, watched: "34m", coverage: 1.0, at: "6:40 PM"),
                MockView(service: .youtube, title: "Why every keyboard sounds different", author: "Alec Steele", format: "standard", embedded: false, watched: "21m", coverage: 0.9, at: "7:20 PM"),
                MockView(service: .youtube, title: "#Shorts — the coffee ring trick", author: "James Hoffmann", format: "short", embedded: false, watched: "2m", coverage: 1.0, at: "7:48 PM"),
            ]
        ),
        MockHistoryDay(
            id: "d-jun12", date: MockDate(year: 2026, month: 6, day: 12), name: "Friday", dateLabel: "Jun 12",
            span: "9:30 PM → 11:33 PM", pastMidnight: false,
            views: [
                MockView(service: .twitch, title: "summit1g — just chatting / Valorant", author: "summit1g", format: "live", embedded: false, watched: "2h 03m", coverage: nil, at: "9:30 PM"),
                MockView(service: .youtube, title: "Deep work playlist (background while coding)", author: "various", format: "standard", embedded: false, watched: "24m", coverage: 0.4, at: "9:35 PM"),
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
