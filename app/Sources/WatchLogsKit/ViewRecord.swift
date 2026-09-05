import Foundation

/// One stored View, exactly as the Extension described it — the header the
/// Events hang off, before anything has been derived from them.
///
/// The read model never surfaces this: History deals in *videos*, folding every
/// View of one video into a row (`HistoryVideo`). This is the grain underneath,
/// and it exists so a tool can ask what was actually recorded before asking what
/// it was turned into.
public struct ViewRecord: Equatable, Sendable, Identifiable {
    public var viewId: String
    public var service: String
    public var contentFormat: String
    public var embedded: Bool
    public var videoId: String
    public var url: String
    public var title: String?
    public var author: String?
    public var durationSec: Double?
    /// Which reader won for this View's metadata — `adapter`, `mediaSession`,
    /// the generic fallback (`metadata.js`'s precedence).
    public var metadataSource: String?
    public var adapterId: String?
    public var tabId: Int
    public var startedAtMs: Int
    /// True while nothing has closed this View. History renders it as
    /// "Still watching".
    public var open: Bool
    /// The View this one succeeded in the same tab, when the page said so.
    public var previousViewId: String?

    public var id: String { viewId }
}
