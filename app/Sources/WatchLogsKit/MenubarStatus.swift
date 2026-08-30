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

    /// Default: a Flush older than this means the Extension has gone quiet. The
    /// Extension flushes every ~5s, so 15s is three missed beats.
    public static let defaultStaleAfter: TimeInterval = 15

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
