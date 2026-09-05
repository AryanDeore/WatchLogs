import Foundation
import WatchLogsKit

/// One place the UI reaches for the shared "Xh Ym" formatter. Wraps
/// `WatchedTimeLine.duration` so every pane and total prints the same way,
/// with the millisecond rounding rule the read model already committed to.
func formatWatchedTime(milliseconds: Int) -> String {
    WatchedTimeLine.duration(milliseconds: milliseconds)
}

/// The History row's own formatter: keeps seconds at the minute scale
/// (`1m23s`), where `formatWatchedTime` would round down to `1m`.
func formatPreciseWatchedTime(milliseconds: Int) -> String {
    WatchedTimeLine.preciseDuration(milliseconds: milliseconds)
}
