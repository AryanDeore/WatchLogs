import Foundation
import Testing
@testable import WatchLogsKit

@Suite("Loopback server", .serialized)
struct LoopbackServerTests {
    // MARK: - Fixtures

    /// Bring up a service on a random high port so parallel machines / other
    /// tests don't collide. Returns the service, a client pointed at it, and the
    /// sink so tests can assert on what was stored.
    static func makeService(
        clock: Clock = SystemClock(),
        basePort: Int? = nil
    ) throws -> (service: LoopbackTransport, client: RawHTTPClient, sink: InMemoryEventSink) {
        let sink = InMemoryEventSink()
        let port = basePort ?? Int.random(in: 49_200..<52_000)
        let config = LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        let service = try LoopbackTransport(
            version: "0.1.0",
            tokenStore: InMemoryTokenStore(),
            clock: clock,
            sink: sink,
            config: config
        )
        try service.start()
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
        return (service, client, sink)
    }

    static func heartbeatBody(flushId: String = UUID().uuidString, schemaVersion: Int = 1) -> Data {
        Data(#"""
        {"schemaVersion":\#(schemaVersion),"flushId":"\#(flushId)","sentAt":1700000000000,\#
        "agent":{"extInstanceId":"ext-1","extVersion":"0.1.0","browser":"chrome","os":"macOS 26"},\#
        "views":[]}
        """#.utf8)
    }

    func bearer(_ service: LoopbackTransport) -> [String: String] {
        ["Authorization": "Bearer \(service.pairing().token)", "Content-Type": "application/json"]
    }

    // MARK: - GET /v1/ping

    @Test("GET /v1/ping returns {app, version, contract} without auth")
    func pingIsUnauthenticated() throws {
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(method: "GET", path: "/v1/ping", includeContentLength: false)
        #expect(response.status == 200)
        let json = try #require(response.json())
        #expect(json["app"] as? String == "WatchLogs")
        #expect(json["version"] as? String == "0.1.0")
        #expect(json["contract"] as? String == "v1")
    }

    // MARK: - POST /v1/flush happy path

    @Test("a valid heartbeat returns a well-formed Ack")
    func heartbeatAck() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_123))
        let (service, client, sink) = try Self.makeService(clock: clock)
        defer { service.stop() }

        let flushId = UUID().uuidString
        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Self.heartbeatBody(flushId: flushId)
        )

        #expect(response.status == 200)
        let json = try #require(response.json())
        #expect(json["flushId"] as? String == flushId)
        #expect(json["accepted"] as? Bool == true)
        #expect(json["views"] as? [Any] != nil)
        #expect((json["views"] as? [Any])?.isEmpty == true)
        #expect(json["serverTime"] as? Int == 1_700_000_123_000)
        #expect(sink.appendCalls == 1)
    }

    // MARK: - Auth

    @Test("a missing token is 401 and the body is never read")
    func missingTokenIs401BeforeBody() throws {
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x20, count: 500_000)
        )

        #expect(response.status == 401)
        #expect(service.server.bodyBytesRead == 0)
        #expect(sink.appendCalls == 0)
    }

    @Test("a wrong token is 401 and the body is never read")
    func wrongTokenIs401BeforeBody() throws {
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(Token.generate().base64)", "Content-Type": "application/json"],
            body: Data(repeating: 0x20, count: 400_000)
        )

        #expect(response.status == 401)
        #expect(service.server.bodyBytesRead == 0)
        #expect(sink.appendCalls == 0)
    }

    // MARK: - CORS preflight

    @Test("OPTIONS /v1/flush is 204 with no Access-Control-Allow-* header")
    func corsPreflightIsBare204() throws {
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(method: "OPTIONS", path: "/v1/flush", includeContentLength: false)
        #expect(response.status == 204)
        for name in response.headers.keys {
            #expect(!name.hasPrefix("access-control-allow"))
        }
    }

    // MARK: - schemaVersion

    @Test("an unknown schemaVersion is 415 {error:schemaVersion} and stores nothing")
    func unknownSchemaVersionRejected() throws {
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Self.heartbeatBody(schemaVersion: 999)
        )

        #expect(response.status == 415)
        #expect(response.json()?["error"] as? String == "schemaVersion")
        #expect(sink.appendCalls == 0)
    }

    @Test("malformed JSON is 400")
    func malformedJSONRejected() throws {
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Data("{not json".utf8)
        )
        #expect(response.status == 400)
        #expect(sink.appendCalls == 0)
    }

    // MARK: - Body cap

    @Test("a body larger than 1 MiB is rejected 413 and not read")
    func oversizedBodyRejected() throws {
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Data(repeating: 0x20, count: (1 << 20) + 1)
        )
        #expect(response.status == 413)
        #expect(service.server.bodyBytesRead == 0)
        #expect(sink.appendCalls == 0)
    }

    @Test("a body of exactly 1 MiB is allowed through to ingest")
    func exactlyOneMiBAllowed() throws {
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }

        // 1 MiB of valid-ish JSON: pad the envelope with a big ignored string.
        let padding = String(repeating: "x", count: (1 << 20) - 200)
        let body = Data(#"""
        {"schemaVersion":1,"flushId":"\#(UUID().uuidString)","sentAt":1,\#
        "agent":{"extInstanceId":"e","extVersion":"0.1.0","browser":"chrome","os":"m"},\#
        "views":[],"_pad":"\#(padding)"}
        """#.utf8)
        #expect(body.count <= (1 << 20))

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: body
        )
        #expect(response.status == 200)
    }

    // MARK: - At-least-once (ADR 0002)

    @Test("re-sending a Flush with the same flushId is accepted again — no front-door de-dup")
    func resentFlushIsAcceptedAgain() throws {
        // ADR 0002: the App keeps no memory of Flushes it has seen. A resend is
        // processed and acked again; a heartbeat carries nothing to double-count.
        let (service, client, sink) = try Self.makeService()
        defer { service.stop() }

        let flushId = UUID().uuidString
        let first = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody(flushId: flushId)
        )
        let second = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody(flushId: flushId)
        )

        #expect(first.status == 200)
        #expect(second.status == 200)
        #expect(first.json()?["flushId"] as? String == flushId)
        #expect(second.json()?["flushId"] as? String == flushId)
        #expect(second.json()?["accepted"] as? Bool == true)
        #expect(sink.appendCalls == 2)
    }

    // MARK: - Regenerate

    @Test("regenerate mints a new token and invalidates the old one")
    func regenerateInvalidatesOldToken() throws {
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }

        let oldToken = service.pairing().token
        let newPairingString = try service.regenerateToken()
        let newToken = try PairingCodec.decode(newPairingString).token
        #expect(oldToken != newToken)

        let withOld = try client.send(
            method: "POST", path: "/v1/flush",
            headers: ["Authorization": "Bearer \(oldToken)", "Content-Type": "application/json"],
            body: Self.heartbeatBody()
        )
        #expect(withOld.status == 401)

        let withNew = try client.send(
            method: "POST", path: "/v1/flush",
            headers: ["Authorization": "Bearer \(newToken)", "Content-Type": "application/json"],
            body: Self.heartbeatBody()
        )
        #expect(withNew.status == 200)
    }

    @Test("the pairing string round-trips to {host, port, token} for the bound port")
    func pairingStringReflectsBoundPort() throws {
        let (service, _, _) = try Self.makeService()
        defer { service.stop() }

        let decoded = try PairingCodec.decode(service.pairingString())
        #expect(decoded.host == "127.0.0.1")
        #expect(decoded.port == service.boundPort)
        #expect(Token(base64: decoded.token) != nil)
    }

    // MARK: - Unknown routes

    @Test("an unknown path is 404")
    func unknownPathIs404() throws {
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }
        let response = try client.send(method: "GET", path: "/v1/nope", includeContentLength: false)
        #expect(response.status == 404)
    }
}
