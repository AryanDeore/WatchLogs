import Foundation

/// The Flush acknowledgement (schema v1):
/// `{flushId, accepted:true, views:[{viewId, ackSeq}], serverTime}`.
public struct Ack: Codable, Equatable, Sendable {
    public var flushId: String
    public var accepted: Bool
    public var views: [ViewAck]
    public var serverTime: Int
    /// Additive, not part of schema v1 proper: set only when the App wants this
    /// Ack to also tell the Extension "flush again right now" (issue #35 §3's
    /// refresh button). The App has no push channel back to the Extension, so
    /// the hint rides the next Ack instead — omitted (rather than `false`) the
    /// rest of the time, and `Optional` here so an Ack persisted before this
    /// field existed still decodes.
    public var flushAgain: Bool?

    public init(flushId: String, accepted: Bool = true, views: [ViewAck], serverTime: Int, flushAgain: Bool? = nil) {
        self.flushId = flushId
        self.accepted = accepted
        self.views = views
        self.serverTime = serverTime
        self.flushAgain = flushAgain
    }

    public struct ViewAck: Codable, Equatable, Sendable {
        public var viewId: String
        public var ackSeq: Int

        public init(viewId: String, ackSeq: Int) {
            self.viewId = viewId
            self.ackSeq = ackSeq
        }
    }

    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
