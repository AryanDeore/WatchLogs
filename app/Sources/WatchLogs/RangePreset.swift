import Foundation
import WatchLogsKit

/// The four UI-side range chips. `DateRangeKind.custom` carries associated
/// `Date` values, so it isn't stable enough for a `Picker` selection tag; this
/// enum stays free of associated values and maps to a `DateRangeKind` when the
/// user actually picks a range.
enum RangePreset: String, CaseIterable, Identifiable, Hashable {
    case today, thisWeek, thisMonth, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .custom: "Custom"
        }
    }

    /// Which chip is highlighted for a given resolved range.
    static func matching(_ kind: DateRangeKind) -> RangePreset {
        switch kind {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .custom: .custom
        }
    }
}
