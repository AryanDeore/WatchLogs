import Foundation
import Observation

/// A display grouping for the menubar popover. Services without a shipped
/// Adapter are intentionally folded into `otherSites` before SwiftUI sees the
/// data, so every displayed total has one stable bucket.
public enum ServiceDisplayBucket: String, CaseIterable, Equatable, Hashable, Sendable {
    case youtube
    case netflix
    case otherSites

    public var name: String {
        switch self {
        case .youtube: "YouTube"
        case .netflix: "Netflix"
        case .otherSites: "Other sites"
        }
    }

    /// Map a stored View's `service` to a display bucket at read time — the one
    /// point every row passes through, old and new alike.
    ///
    /// A View's `service` arrives in one of two shapes and we accept both: the
    /// Adapter id (`"youtube"`) that a shipped Adapter and the dev scripts send,
    /// and the bare hostname (`"youtube.com"`, `"youtu.be"`) the current
    /// Adapter-less extension slice sends. Anything unrecognised is `otherSites`,
    /// so the worst case for a new site is a generic icon, never a failure.
    static func from(service: String) -> ServiceDisplayBucket {
        let key = service.lowercased().hasPrefix("www.")
            ? String(service.lowercased().dropFirst(4))
            : service.lowercased()

        if youtubeServices.contains(key) { return .youtube }
        if netflixServices.contains(key) { return .netflix }
        return .otherSites
    }

    private static let youtubeServices: Set<String> = [
        "youtube", "youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
    ]

    private static let netflixServices: Set<String> = [
        "netflix", "netflix.com",
    ]
}

public enum MenubarPane: String, CaseIterable, Equatable, Sendable {
    case history
    case byService
    case trends

    public var title: String {
        switch self {
        case .history: "History"
        case .byService: "By Service"
        case .trends: "Trends"
        }
    }
}

/// One service's display total. `formats` remains at the rollup grain, which
/// lets the By Service pane expand YouTube without recomputing in SwiftUI.
public struct ServiceDisplayBucketTotal: Equatable, Sendable, Identifiable {
    public var service: ServiceDisplayBucket
    public var totals: Totals
    public var formats: [TotalsSlice]
    /// Watched time for YouTube Views playing inside a third-party page.
    public var embeddedWatchedMs: Int
    /// Share of range Watched time. SwiftUI renders this directly.
    public var watchedFraction: Double

    public init(service: ServiceDisplayBucket, totals: Totals, formats: [TotalsSlice], embeddedWatchedMs: Int = 0, watchedFraction: Double = 0) {
        self.service = service
        self.totals = totals
        self.formats = formats
        self.embeddedWatchedMs = embeddedWatchedMs
        self.watchedFraction = watchedFraction
    }

    public var id: ServiceDisplayBucket { service }
}

/// A Day's stack in the Trends pane. The model returns one for every resolved
/// Day, including a Day with no `rollup_slice` children.
public struct DaySeriesEntry: Equatable, Sendable, Identifiable {
    public var label: String
    public var totals: [ServiceDisplayBucket: Totals]

    public var id: String { label }
    public var totalMs: Int { totals.values.reduce(0) { $0 + $1.watchedMs } }
    /// Fraction of the largest resolved Day, shared by horizontal and vertical Trends.
    public var scaleFraction: Double = 0
}

/// One row in the History pane: a *video* watched during a Day, not a single
/// View. Every View of the same video that day (a re-watch, a scroll back to an
/// earlier Short, a player that re-mounted) is folded into this one row —
/// `watchedMs` sums them, `coverage` unions them, `watchCount` counts them.
/// Everything stored underneath stays at View grain; this is a read-time
/// rollup, the same move `ServiceDisplayBucket` makes for services.
public struct HistoryVideo: Equatable, Sendable, Identifiable {
    /// Stable within a Day: the display bucket and video id joined. Not a View id.
    public var id: String
    public var videoId: String
    public var service: ServiceDisplayBucket
    public var sourceService: String
    public var contentFormat: String
    public var embedded: Bool
    public var title: String?
    public var author: String?
    /// When the first watched Segment of this video that Day began.
    public var firstWatchedAt: Date
    /// When the most recent watched Segment of this video ended — what the row
    /// is sorted by, and the time shown on the row.
    public var lastWatchedAt: Date
    public var watchedMs: Int
    /// How many separate Views of this video landed in the Day (1 when it was
    /// watched once).
    public var watchCount: Int
    public var knownDurationSec: Double?
    public var isOpen: Bool
    /// The video playing right now: an open View whose watched time reaches up
    /// to the moment the pane was resolved. Sorted to the very top.
    public var isPlaying: Bool
    /// `nil` for live videos and videos without a known duration.
    public var coverage: Double?
}

public struct HistoryDay: Equatable, Sendable, Identifiable {
    public var label: String
    public var watchedMs: Int
    public var isOpen: Bool
    /// The wall-clock span of watching activity on this Day: the first watched
    /// Segment's start through the last one's end. Equal instants when the Day
    /// holds a single short View.
    public var firstAt: Date
    public var lastAt: Date
    public var videos: [HistoryVideo]

    public var id: String { label }
}

/// Everything the three panes and the title row need for one resolved range.
public struct MenubarPopoverData: Equatable, Sendable {
    public var range: DateRangeKind
    public var rangeLabel: String
    public var total: Totals
    public var summary: [ServiceDisplayBucketTotal]
    public var services: [ServiceDisplayBucketTotal]
    public var history: [HistoryDay]
    public var trends: [DaySeriesEntry]
    public var activityDay: Date
    public var activityDayLabel: String
}

/// The public backing model for the native menubar popover. It owns typed UI
/// state and resolves all presentation data from the EventStore; views only
/// render `resolved` and never total segments themselves.
@Observable
public final class MenubarPopoverReadModel {
    public var range: DateRangeKind
    public var pane: MenubarPane
    public var calendarExpanded: Bool
    public var customStart: Date?
    public var customEnd: Date?
    public var youtubeExpanded: Bool
    public var otherExpanded: Bool
    public var settingsOpen: Bool

    private let store: EventStore
    private let clock: Clock
    private let calendar: Calendar

    public init(
        store: EventStore,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current,
        range: DateRangeKind = .today,
        pane: MenubarPane = .history
    ) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.range = range
        self.pane = pane
        self.calendarExpanded = false
        self.customStart = nil
        self.customEnd = nil
        self.youtubeExpanded = false
        self.otherExpanded = false
        self.settingsOpen = false
    }

    public var resolved: MenubarPopoverData {
        let now = clock.now()
        let unscaledServices = (try? store.displayServiceTotals(for: range, now: now, calendar: calendar)) ?? []
        let total = unscaledServices.reduce(into: Totals()) { total, service in
            total.watchedMs += service.totals.watchedMs
            total.backgroundMs += service.totals.backgroundMs
        }
        let services = unscaledServices.map { item in
            var item = item
            item.watchedFraction = total.watchedMs == 0 ? 0 : Double(item.totals.watchedMs) / Double(total.watchedMs)
            return item
        }
        let unscaledTrends = (try? store.dailySeries(for: range, now: now, calendar: calendar)) ?? []
        let largestDay = max(unscaledTrends.map(\.totalMs).max() ?? 0, 1)
        let trends = unscaledTrends.map { day in
            var day = day
            day.scaleFraction = Double(day.totalMs) / Double(largestDay)
            return day
        }
        let activityDay = (try? store.activityDay(now: now, calendar: calendar)) ?? now
        return MenubarPopoverData(
            range: range,
            rangeLabel: (try? store.rangeLabel(for: range, now: now, calendar: calendar)) ?? "",
            total: total,
            summary: Array(services.sorted { $0.totals.watchedMs > $1.totals.watchedMs }.prefix(3)),
            services: services,
            history: (try? store.history(for: range, now: now, calendar: calendar)) ?? [],
            trends: trends,
            activityDay: activityDay,
            activityDayLabel: DayBoundary.label(for: activityDay, calendar: calendar)
        )
    }

    /// Changes which Days are resolved while deliberately preserving `pane`.
    public func selectRange(_ range: DateRangeKind) {
        self.range = range
        calendarExpanded = false
    }

    public func selectCustomDay(_ day: Date) {
        if customStart == nil || customEnd != nil {
            customStart = day
            customEnd = nil
        } else if day < customStart! {
            customEnd = customStart
            customStart = day
        } else {
            customEnd = day
        }
        let end = customEnd ?? customStart ?? day
        range = .custom(from: customStart ?? day, through: end)
        calendarExpanded = true
    }
}
