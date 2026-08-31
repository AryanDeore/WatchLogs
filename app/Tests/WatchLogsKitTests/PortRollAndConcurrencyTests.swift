import Foundation
import Testing
@testable import WatchLogsKit

@Suite("Port roll and concurrency", .serialized)
struct PortRollAndConcurrencyTests {
    @Test("a collision on the default port rolls forward to a free port")
    func portCollisionRollsForward() throws {
        let basePort = Int.random(in: 49_200..<52_000)

        // Occupy the default port with a first service.
        let firstConfig = LoopbackServer.Config(version: "0.1.0", defaultPort: basePort)
        let first = try LoopbackTransport(
            version: "0.1.0", tokenStore: InMemoryTokenStore(),
            store: try EventStore(path: ":memory:"), config: firstConfig
        )
        try first.start()
        defer { first.stop() }
        #expect(first.boundPort == basePort)

        // A second service asked for the same default port must land elsewhere.
        let secondConfig = LoopbackServer.Config(version: "0.1.0", defaultPort: basePort)
        let second = try LoopbackTransport(
            version: "0.1.0", tokenStore: InMemoryTokenStore(),
            store: try EventStore(path: ":memory:"), config: secondConfig
        )
        try second.start()
        defer { second.stop() }

        let boundPort = try #require(second.boundPort)
        #expect(boundPort != basePort)
        #expect(boundPort > basePort)

        // The pairing string reflects the port actually bound.
        #expect(try PairingCodec.decode(second.pairingString()).port == boundPort)

        // ...and that port really works.
        let client = RawHTTPClient(host: "127.0.0.1", port: boundPort)
        let ping = try client.send(method: "GET", path: "/v1/ping", includeContentLength: false)
        #expect(ping.status == 200)
    }

    @Test("giving up after every rolled port is taken throws noFreePort")
    func exhaustedPortRangeThrows() throws {
        let basePort = Int.random(in: 49_200..<52_000)
        let config = LoopbackServer.Config(version: "0.1.0", defaultPort: basePort, portRollAttempts: 1)

        let holder = try LoopbackTransport(
            version: "0.1.0", tokenStore: InMemoryTokenStore(),
            store: try EventStore(path: ":memory:"), config: config
        )
        try holder.start()
        defer { holder.stop() }

        let blocked = try LoopbackTransport(
            version: "0.1.0", tokenStore: InMemoryTokenStore(),
            store: try EventStore(path: ":memory:"), config: config
        )
        #expect(throws: LoopbackServer.StartError.self) {
            try blocked.start()
        }
    }

    @Test("overlapping Flushes are serialised — never more than one in ingest at a time")
    func concurrentFlushesSerialised() throws {
        let store = try EventStore(path: ":memory:")
        let basePort = Int.random(in: 49_200..<52_000)
        let config = LoopbackServer.Config(version: "0.1.0", defaultPort: basePort)
        // Widen the ingest critical section so a real race would be caught.
        let ingest = Ingest(clock: SystemClock(), store: store, criticalSectionPadding: 0.03)
        let tokenStore = InMemoryTokenStore(token: Token.generate())
        let token = try #require(try tokenStore.load())
        let server = LoopbackServer(config: config, tokenProvider: { token.raw }, ingest: ingest)
        try server.start()
        defer { server.stop() }

        let boundPort = try #require(server.boundPort)
        let bearer = ["Authorization": "Bearer \(token.base64)", "Content-Type": "application/json"]

        let group = DispatchGroup()
        let statusesLock = NSLock()
        var statuses: [Int] = []

        for _ in 0..<6 {
            group.enter()
            DispatchQueue.global().async {
                let client = RawHTTPClient(host: "127.0.0.1", port: boundPort)
                let body = LoopbackServerTests.heartbeatBody()
                if let response = try? client.send(method: "POST", path: "/v1/flush", headers: bearer, body: body) {
                    statusesLock.lock(); statuses.append(response.status); statusesLock.unlock()
                }
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 10) == .success)

        #expect(statuses.count == 6)
        #expect(statuses.allSatisfy { $0 == 200 })
        #expect(ingest.maxObservedConcurrency == 1)
        #expect(try store.counts().flushes == 6)
    }
}
