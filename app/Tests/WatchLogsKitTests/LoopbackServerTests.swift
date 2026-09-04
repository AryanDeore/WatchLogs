import Foundation
import Testing
@testable import WatchLogsKit

@Suite("Loopback server", .serialized)
struct LoopbackServerTests {
    // MARK: - Fixtures

    /// Bring up a service on a random high port so parallel machines / other
    /// tests don't collide. Returns the service, a client pointed at it, and the
    /// store so tests can assert on what was stored. The store is a real SQLite
    /// database held in memory — the same SQL production runs.
    static func makeService(
        clock: Clock = SystemClock(),
        basePort: Int? = nil
    ) throws -> (service: LoopbackTransport, client: RawHTTPClient, store: EventStore) {
        let store = try EventStore(path: ":memory:")
        let port = basePort ?? Int.random(in: 49_200..<52_000)
        let config = LoopbackServer.Config(version: "0.1.0", defaultPort: port)
        let service = try LoopbackTransport(
            version: "0.1.0",
            tokenStore: InMemoryTokenStore(),
            store: store,
            clock: clock,
            config: config
        )
        try service.start()
        let client = RawHTTPClient(host: "127.0.0.1", port: try #require(service.boundPort))
        return (service, client, store)
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

    // MARK: - GET /v1/settings

    @Test("GET /v1/settings requires auth and returns the persisted private-window setting")
    func settingsRequiresAuthAndReturnsPersistedValue() throws {
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let unauthorized = try client.send(method: "GET", path: "/v1/settings", includeContentLength: false)
        #expect(unauthorized.status == 401)

        let initial = try client.send(method: "GET", path: "/v1/settings", headers: bearer(service), includeContentLength: false)
        #expect(initial.status == 200)
        #expect(initial.json()?["capturePrivateWindows"] as? Bool == false)

        try store.setCapturesPrivateWindows(true)
        let changed = try client.send(method: "GET", path: "/v1/settings", headers: bearer(service), includeContentLength: false)
        #expect(changed.status == 200)
        #expect(changed.json()?["capturePrivateWindows"] as? Bool == true)
    }

    // MARK: - POST /v1/flush happy path

    @Test("a valid heartbeat returns a well-formed Ack")
    func heartbeatAck() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_123))
        let (service, client, store) = try Self.makeService(clock: clock)
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
        #expect(try store.counts().flushes == 1)
    }

    // MARK: - Auth

    @Test("a missing token is 401 and the body is never read")
    func missingTokenIs401BeforeBody() throws {
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x20, count: 500_000)
        )

        #expect(response.status == 401)
        #expect(service.server.bodyBytesRead == 0)
        #expect(try store.counts() == EventStore.Counts())
    }

    @Test("a wrong token is 401 and the body is never read")
    func wrongTokenIs401BeforeBody() throws {
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: ["Authorization": "Bearer \(Token.generate().base64)", "Content-Type": "application/json"],
            body: Data(repeating: 0x20, count: 400_000)
        )

        #expect(response.status == 401)
        #expect(service.server.bodyBytesRead == 0)
        #expect(try store.counts() == EventStore.Counts())
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
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Self.heartbeatBody(schemaVersion: 999)
        )

        #expect(response.status == 415)
        #expect(response.json()?["error"] as? String == "schemaVersion")
        #expect(try store.counts() == EventStore.Counts())
    }

    @Test("malformed JSON is 400")
    func malformedJSONRejected() throws {
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Data("{not json".utf8)
        )
        #expect(response.status == 400)
        #expect(try store.counts() == EventStore.Counts())
    }

    // MARK: - Body cap

    @Test("a body larger than 1 MiB is rejected 413 and not read")
    func oversizedBodyRejected() throws {
        let (service, client, store) = try Self.makeService()
        defer { service.stop() }

        let response = try client.send(
            method: "POST",
            path: "/v1/flush",
            headers: bearer(service),
            body: Data(repeating: 0x20, count: (1 << 20) + 1)
        )
        #expect(response.status == 413)
        #expect(service.server.bodyBytesRead == 0)
        #expect(try store.counts() == EventStore.Counts())
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

    @Test("re-sending a Flush with the same flushId replays the stored Ack")
    func resentFlushReplaysTheStoredAck() throws {
        // ADR 0002 + SCHEMA §7: the Extension resends a batch whose Ack it never
        // saw, reusing the flushId. The App replays the first Ack verbatim —
        // right down to its serverTime — and stores nothing the second time.
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (service, client, store) = try Self.makeService(clock: clock)
        defer { service.stop() }

        let flushId = UUID().uuidString
        let first = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody(flushId: flushId)
        )
        clock.advance(by: 30)
        let second = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody(flushId: flushId)
        )

        #expect(first.status == 200)
        #expect(second.status == 200)
        #expect(first.json()?["flushId"] as? String == flushId)
        #expect(second.json()?["accepted"] as? Bool == true)
        // Replayed, not recomputed: the second Ack carries the first one's clock.
        #expect(second.json()?["serverTime"] as? Int == 1_700_000_000_000)
        #expect(try store.counts().flushes == 1)
    }

    @Test("requestFlushAgain arms exactly the next accepted Flush's Ack, then clears itself")
    func requestFlushAgainArmsOneAckOnly() throws {
        // Issue #35 §3: the App has no push channel to the Extension, so the
        // refresh button's hint has to ride the next Ack — and only that one,
        // or the Extension would loop re-flushing forever.
        let (service, client, _) = try Self.makeService()
        defer { service.stop() }

        let before = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody()
        )
        #expect(before.json()?["flushAgain"] == nil)

        service.requestFlushAgain()

        let hinted = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody()
        )
        #expect(hinted.json()?["flushAgain"] as? Bool == true)

        let after = try client.send(
            method: "POST", path: "/v1/flush",
            headers: bearer(service), body: Self.heartbeatBody()
        )
        #expect(after.json()?["flushAgain"] == nil)
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
