import Foundation

/// Wires the token store, the pairing string, and the loopback server together —
/// the whole App side of issue #26 behind one object.
///
/// Named "transport", not "service": `CONTEXT.md` reserves **Service** for the
/// video platform a View belongs to.
///
/// The current token is held in memory (loaded from the store at init), so
/// "regenerate" takes effect for the very next request and the old token stops
/// working immediately.
public final class LoopbackTransport: @unchecked Sendable {
    public let server: LoopbackServer
    /// The Event log and read model every Flush lands in, and the menubar reads.
    public let store: EventStore

    private let tokenStore: TokenStore
    private let clock: Clock
    private let token: Locked<Token>

    public init(
        version: String,
        tokenStore: TokenStore,
        store: EventStore,
        clock: Clock = SystemClock(),
        config: LoopbackServer.Config? = nil,
        onFlush: (@Sendable () -> Void)? = nil
    ) throws {
        self.tokenStore = tokenStore
        self.store = store
        self.clock = clock
        let held = Locked<Token>(try tokenStore.loadOrCreate())
        self.token = held

        let ingest = Ingest(clock: clock, store: store, onAccepted: onFlush)
        self.server = LoopbackServer(
            config: config ?? LoopbackServer.Config(version: version),
            tokenProvider: { held.current.raw },
            ingest: ingest
        )
    }

    /// Watched and Background time for the naive local calendar day containing
    /// `now` — the menubar's "Watched today" number.
    public func todayTotals() throws -> Totals {
        try store.totals(in: DateRange.day(containing: clock.now()))
    }

    /// Bind the server (rolling the port on collision).
    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }

    /// The port actually bound, once `start()` has succeeded.
    public var boundPort: Int? { server.boundPort }

    /// The `{host, port, token}` triple for the port actually bound.
    public func pairing() -> Pairing {
        Pairing(
            host: LoopbackDefaults.host,
            port: server.boundPort ?? 0,
            token: token.current.base64
        )
    }

    /// The base64 pairing string shown in Settings and pasted into the Extension.
    public func pairingString() -> String {
        PairingCodec.encode(pairing())
    }

    /// Mint a new token, persist it, and make it live. Any caller still holding
    /// the previous token now fails auth. Returns the new pairing string.
    @discardableResult
    public func regenerateToken() throws -> String {
        token.set(try tokenStore.regenerate())
        return pairingString()
    }
}
