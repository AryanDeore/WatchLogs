import Foundation

/// The Flush acknowledgement (schema v1):
/// `{flushId, accepted:true, views:[{viewId, ackSeq}], serverTime}`.
public struct Ack: Codable, Equatable, Sendable {
    public var flushId: String
    public var accepted: Bool
    public var views: [ViewAck]
    public var serverTime: Int

    public init(flushId: String, accepted: Bool = true, views: [ViewAck], serverTime: Int) {
        self.flushId = flushId
        self.accepted = accepted
        self.views = views
        self.serverTime = serverTime
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
