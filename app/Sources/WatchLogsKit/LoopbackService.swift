import Foundation

/// Wires the token store, the pairing string, and the loopback server together —
/// the whole App side of issue #26 behind one object.
///
/// The current token is held in memory (loaded from the store at init), so
/// "regenerate" takes effect for the very next request and the old token stops
/// working immediately.
public final class LoopbackService: @unchecked Sendable {
    public let server: LoopbackServer

    private let tokenStore: TokenStore
    private let token: TokenBox

    public init(
        version: String,
        tokenStore: TokenStore,
        clock: Clock = SystemClock(),
        sink: EventSink = InMemoryEventSink(),
        config: LoopbackServer.Config? = nil,
        onFlush: (@Sendable () -> Void)? = nil
    ) throws {
        self.tokenStore = tokenStore
        let box = TokenBox(token: try tokenStore.loadOrCreate())
        self.token = box

        let ingest = Ingest(clock: clock, sink: sink, onAccepted: onFlush)
        self.server = LoopbackServer(
            config: config ?? LoopbackServer.Config(version: version),
            tokenProvider: { box.value.raw },
            ingest: ingest
        )
    }

    /// Bind the server (rolling the port on collision).
    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }

    /// The `{host, port, token}` triple for the port actually bound.
    public func pairing() -> Pairing {
        Pairing(
            host: LoopbackDefaults.host,
            port: server.boundPort ?? 0,
            token: token.value.base64
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
        token.value = try tokenStore.regenerate()
        return pairingString()
    }
}

/// A thread-safe holder so the server's `tokenProvider` closure always sees the
/// current token without capturing `self`.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Token
    init(token: Token) { _value = token }
    var value: Token {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
