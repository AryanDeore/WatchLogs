import Foundation

/// The single status line the menubar shows (issue #26):
/// "Connected · last flush <n>s ago", or a disconnected / needs-pairing state.
///
/// A pure function of "when did the last Flush land" and "what time is it now",
/// so it is testable without a running server or a real menubar.
public enum MenubarStatus: Equatable, Sendable {
    /// No Flush has ever been received — the user still needs to pair.
    case notPaired
    /// A Flush landed within `staleAfter`.
    case connected(secondsSinceLastFlush: Int)
    /// Flushes were arriving but have now gone quiet.
    case disconnected(secondsSinceLastFlush: Int)

    /// Default: a Flush older than this means the Extension has gone quiet.
    ///
    /// The Extension Flushes every 5s while a View is playing, and otherwise only
    /// on its 30s buffer sweep — so an idle browser is silent for 30s at a time
    /// and 45s is one and a half missed sweeps, not a fault.
    public static let defaultStaleAfter: TimeInterval = 45

    public static func evaluate(
        lastFlushAt: Date?,
        now: Date,
        staleAfter: TimeInterval = MenubarStatus.defaultStaleAfter
    ) -> MenubarStatus {
        guard let lastFlushAt else { return .notPaired }
        let elapsed = max(0, now.timeIntervalSince(lastFlushAt))
        let seconds = Int(elapsed.rounded(.down))
        if elapsed <= staleAfter {
            return .connected(secondsSinceLastFlush: seconds)
        }
        return .disconnected(secondsSinceLastFlush: seconds)
    }

    public var line: String {
        switch self {
        case .notPaired:
            return "Not paired yet — copy the pairing string into the extension"
        case .connected(let seconds):
            return "Connected · last flush \(seconds)s ago"
        case .disconnected(let seconds):
            return "Disconnected · last flush \(MenubarStatus.humanize(seconds)) ago"
        }
    }

    private static func humanize(_ seconds: Int) -> String {
        if seconds < 120 { return "\(seconds)s" }
        return "\(seconds / 60) min"
    }
}

/// The menubar's "Watched today" line — the one number the App puts in front of
/// the user this slice, read from `totals(today)`.
///
/// Formatting matches the popover prototype (`prototypes/menubar-layout/`):
/// `2h 05m` at the hour scale, dropping to minutes and then seconds so a
/// just-started session shows something other than `0h 00m`.
public enum WatchedTimeLine {
    public static func today(_ totals: Totals) -> String {
        "Watched today · \(duration(milliseconds: totals.watchedMs))"
    }

    /// Milliseconds in, one rounding to whole seconds, out.
    public static func duration(milliseconds: Int) -> String {
        let seconds = Totals.seconds(max(0, milliseconds))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
