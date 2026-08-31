import Foundation

/// The Flush wire schema (v1), from `prototypes/message-schema/SCHEMA.md`.
public struct FlushEnvelope: Sendable {
    public var schemaVersion: Int
    public var flushId: String
    public var sentAt: Int
    public var agent: Agent
    public var views: [FlushView]

    public struct Agent: Codable, Sendable, Equatable {
        public var extInstanceId: String
        public var extVersion: String
        public var browser: String
        public var os: String
    }
}

/// One View inside a Flush: the header the App mirrors into `views`, plus the
/// Events above the last Ack'd `seq`.
///
/// The header always carries the View's latest known metadata, so a later Flush
/// overwrites what an earlier one said; the `metadataChange` Events keep the
/// history of when each field resolved.
public struct FlushView: Sendable {
    public var viewId: String
    public var service: String
    public var contentFormat: String
    public var embedded: Bool
    public var videoId: String
    public var url: String
    public var title: String?
    public var author: String?
    public var durationSec: Double?
    public var metadataSource: String?
    public var adapterId: String?
    public var tabId: Int
    public var startedAt: Int
    /// Mirrors "this batch does not carry the View's `viewEnded`". Advisory
    /// only: whether a Segment is `provisional` is decided by the Event log.
    public var open: Bool
    public var previousViewId: String?
    public var events: [RawEvent]

    public init(
        viewId: String,
        service: String = "",
        contentFormat: String = "standard",
        embedded: Bool = false,
        videoId: String = "",
        url: String = "",
        title: String? = nil,
        author: String? = nil,
        durationSec: Double? = nil,
        metadataSource: String? = nil,
        adapterId: String? = nil,
        tabId: Int = 0,
        startedAt: Int = 0,
        open: Bool = true,
        previousViewId: String? = nil,
        events: [RawEvent] = []
    ) {
        self.viewId = viewId
        self.service = service
        self.contentFormat = contentFormat
        self.embedded = embedded
        self.videoId = videoId
        self.url = url
        self.title = title
        self.author = author
        self.durationSec = durationSec
        self.metadataSource = metadataSource
        self.adapterId = adapterId
        self.tabId = tabId
        self.startedAt = startedAt
        self.open = open
        self.previousViewId = previousViewId
        self.events = events
    }
}

/// The outcome of handing a raw request body to `Ingest`.
public enum IngestOutcome: Sendable, Equatable {
    /// `200` with this Ack body.
    case accepted(Ack)
    /// `400` — the body was not a Flush we could parse. `error` is a short reason.
    case badRequest(error: String)
    /// `415 {error:"schemaVersion"}` — a recognised envelope with an unknown
    /// top-level `schemaVersion`. Nothing is stored.
    case unsupportedSchemaVersion
    /// `500` — the Flush was valid but could not be stored. Deliberately not an
    /// Ack: the Extension keeps the batch and retries rather than pruning it.
    case storageFailure
}

/// Decodes a Flush envelope.
///
/// Strict about the envelope and the View header — a missing required field
/// there means the Extension and the App disagree about schema v1, and `400`
/// tells it to drop the batch. Lenient below that: an unknown event `type` or
/// `viewEnded.reason` is additive by design and is recorded uninterpreted, and a
/// type-specific field that is absent is left nil for the state machine to
/// treat as "no information" rather than a reason to reject the whole Flush.
enum FlushEnvelopeDecoder {
    static let supportedSchemaVersion = 1

    enum DecodeResult {
        case ok(FlushEnvelope)
        case badRequest(String)
        case unsupportedSchemaVersion
    }

    /// One decoded piece, or the short reason the whole Flush is a `400`.
    enum Decoded<Value> {
        case value(Value)
        case invalid(String)
    }

    static func decode(_ body: Data) -> DecodeResult {
        guard
            let any = try? JSONSerialization.jsonObject(with: body),
            let object = any as? [String: Any]
        else {
            return .badRequest("malformed JSON")
        }

        // schemaVersion is checked before anything else so an unknown version is
        // a clean 415 rather than a 400 about some other missing field.
        guard let schemaValue = object["schemaVersion"] else {
            return .badRequest("missing schemaVersion")
        }
        guard let schemaVersion = JSONNumber.whole(schemaValue) else {
            return .badRequest("schemaVersion must be an integer")
        }
        guard schemaVersion == supportedSchemaVersion else {
            return .unsupportedSchemaVersion
        }

        guard let flushId = object["flushId"] as? String, !flushId.isEmpty else {
            return .badRequest("missing flushId")
        }
        guard let sentAtValue = object["sentAt"], let sentAt = JSONNumber.whole(sentAtValue) else {
            return .badRequest("missing sentAt")
        }
        guard
            let agentObject = object["agent"] as? [String: Any],
            let agent = decodeAgent(agentObject)
        else {
            return .badRequest("missing agent")
        }
        guard let viewsArray = object["views"] as? [Any] else {
            return .badRequest("missing views")
        }

        var views: [FlushView] = []
        views.reserveCapacity(viewsArray.count)
        for element in viewsArray {
            guard let viewObject = element as? [String: Any] else {
                return .badRequest("view must be an object")
            }
            switch decodeView(viewObject) {
            case .value(let view): views.append(view)
            case .invalid(let reason): return .badRequest(reason)
            }
        }

        return .ok(FlushEnvelope(
            schemaVersion: schemaVersion,
            flushId: flushId,
            sentAt: sentAt,
            agent: agent,
            views: views
        ))
    }

    private static func decodeAgent(_ object: [String: Any]) -> FlushEnvelope.Agent? {
        guard
            let extInstanceId = object["extInstanceId"] as? String,
            let extVersion = object["extVersion"] as? String,
            let browser = object["browser"] as? String,
            let os = object["os"] as? String
        else { return nil }
        return FlushEnvelope.Agent(
            extInstanceId: extInstanceId,
            extVersion: extVersion,
            browser: browser,
            os: os
        )
    }

    private static func decodeView(_ object: [String: Any]) -> Decoded<FlushView> {
        guard let viewId = object["viewId"] as? String, !viewId.isEmpty else {
            return .invalid("view missing viewId")
        }
        guard let service = object["service"] as? String, !service.isEmpty else {
            return .invalid("view missing service")
        }
        guard let contentFormat = object["contentFormat"] as? String, !contentFormat.isEmpty else {
            return .invalid("view missing contentFormat")
        }
        guard let embeddedValue = object["embedded"], let embedded = JSONNumber.flag(embeddedValue) else {
            return .invalid("view missing embedded")
        }
        guard let videoId = object["videoId"] as? String, !videoId.isEmpty else {
            return .invalid("view missing videoId")
        }
        guard let url = object["url"] as? String else {
            return .invalid("view missing url")
        }
        guard let tabIdValue = object["tabId"], let tabId = JSONNumber.whole(tabIdValue) else {
            return .invalid("view missing tabId")
        }
        guard let startedAtValue = object["startedAt"], let startedAt = JSONNumber.whole(startedAtValue) else {
            return .invalid("view missing startedAt")
        }
        guard let openValue = object["open"], let open = JSONNumber.flag(openValue) else {
            return .invalid("view missing open")
        }
        guard let eventsArray = object["events"] as? [Any] else {
            return .invalid("view missing events")
        }

        var events: [RawEvent] = []
        events.reserveCapacity(eventsArray.count)
        for element in eventsArray {
            guard let eventObject = element as? [String: Any] else {
                return .invalid("event must be an object")
            }
            switch decodeEvent(eventObject) {
            case .value(let event): events.append(event)
            case .invalid(let reason): return .invalid(reason)
            }
        }

        return .value(FlushView(
            viewId: viewId,
            service: service,
            contentFormat: contentFormat,
            embedded: embedded,
            videoId: videoId,
            url: url,
            title: object["title"] as? String,
            author: object["author"] as? String,
            durationSec: object["durationSec"].flatMap(JSONNumber.real),
            metadataSource: object["metadataSource"] as? String,
            adapterId: object["adapterId"] as? String,
            tabId: tabId,
            startedAt: startedAt,
            open: open,
            previousViewId: object["previousViewId"] as? String,
            events: events
        ))
    }

    private static func decodeEvent(_ object: [String: Any]) -> Decoded<RawEvent> {
        guard let seqValue = object["seq"], let seq = JSONNumber.whole(seqValue), seq >= 1 else {
            return .invalid("event missing seq")
        }
        guard let type = object["type"] as? String, !type.isEmpty else {
            return .invalid("event missing type")
        }
        guard let tValue = object["t"], let t = JSONNumber.whole(tValue) else {
            return .invalid("event missing t")
        }

        return .value(RawEvent(
            seq: seq,
            type: EventType(name: type),
            t: t,
            pos: object["pos"].flatMap(JSONNumber.real),
            from: object["from"].flatMap(JSONNumber.real),
            to: object["to"].flatMap(JSONNumber.real),
            rate: object["rate"].flatMap(JSONNumber.real),
            playing: object["playing"].flatMap(JSONNumber.flag),
            visible: object["visible"].flatMap(JSONNumber.flag),
            reason: object["reason"] as? String
        ))
    }
}
