import Foundation
import WatchLogsKit

/// One place the UI reaches for the shared "Xh Ym" formatter. Wraps
/// `WatchedTimeLine.duration` so every pane and total prints the same way,
/// with the millisecond rounding rule the read model already committed to.
func formatWatchedTime(milliseconds: Int) -> String {
    WatchedTimeLine.duration(milliseconds: milliseconds)
}
