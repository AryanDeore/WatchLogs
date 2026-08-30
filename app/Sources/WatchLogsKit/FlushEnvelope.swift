import Foundation

/// The Flush wire schema (v1), from `prototypes/message-schema/SCHEMA.md`.
///
/// Issue #26 only exercises the heartbeat — an envelope whose `views` array is
/// empty — so the per-View shape here is deliberately permissive: enough to
/// accept and echo a populated Flush, not the full validation that lands with
/// Segment computation (slice 2).
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

/// A View inside a Flush. Only `viewId` and `events` are read this slice; the
/// rest is carried through untouched.
public struct FlushView: Sendable {
    public var viewId: String
    public var events: [FlushEvent]

    public struct FlushEvent: Sendable {
        public var seq: Int
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
}

/// Decoding a Flush envelope with the three distinct failure shapes issue #26
/// cares about: not-JSON, unknown-schemaVersion, missing-required-field.
enum FlushEnvelopeDecoder {
    static let supportedSchemaVersion = 1

    enum DecodeResult {
        case ok(FlushEnvelope)
        case badRequest(String)
        case unsupportedSchemaVersion
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
        guard let schemaVersion = wholeNumber(schemaValue) else {
            return .badRequest("schemaVersion must be an integer")
        }
        guard schemaVersion == supportedSchemaVersion else {
            return .unsupportedSchemaVersion
        }

        guard let flushId = object["flushId"] as? String, !flushId.isEmpty else {
            return .badRequest("missing flushId")
        }
        guard let sentAtValue = object["sentAt"], let sentAt = wholeNumber(sentAtValue) else {
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
                return .badRequest("view is not an object")
            }
            guard let viewId = viewObject["viewId"] as? String, !viewId.isEmpty else {
                return .badRequest("view missing viewId")
            }
            let events: [FlushView.FlushEvent] = (viewObject["events"] as? [Any] ?? []).compactMap { raw in
                guard let eventObject = raw as? [String: Any],
                      let seqValue = eventObject["seq"], let seq = wholeNumber(seqValue) else { return nil }
                return FlushView.FlushEvent(seq: seq)
            }
            views.append(FlushView(viewId: viewId, events: events))
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

    /// A JSON number that is an exact integer (rejects `1.5`, accepts `1` / `1.0`).
    private static func wholeNumber(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // NSNumber wrapping a bool must not count as a number here.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let intValue = number.intValue
        return Double(intValue) == number.doubleValue ? intValue : nil
    }
}
