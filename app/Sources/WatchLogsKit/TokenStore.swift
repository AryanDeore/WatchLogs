import Foundation

/// Where the App keeps its bearer token. The production implementation is the
/// macOS Keychain; tests use `InMemoryTokenStore`. The token is never written to
/// a plaintext app file (issue #26 acceptance).
public protocol TokenStore: Sendable {
    /// The stored token, or `nil` if none has been minted yet.
    func load() throws -> Token?
    /// Persist `token`, replacing any existing one.
    func save(_ token: Token) throws
    /// Remove any stored token.
    func clear() throws
}

extension TokenStore {
    /// Return the stored token, minting and persisting one on first run.
    func loadOrCreate() throws -> Token {
        if let existing = try load() { return existing }
        let fresh = Token.generate()
        try save(fresh)
        return fresh
    }

    /// Mint a new token, persist it, and return it. The previous token is gone
    /// and any caller still presenting it now fails auth.
    @discardableResult
    func regenerate() throws -> Token {
        let fresh = Token.generate()
        try save(fresh)
        return fresh
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: Token?

    public init(token: Token? = nil) {
        self.token = token
    }

    public func load() throws -> Token? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func save(_ token: Token) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        token = nil
    }
}
