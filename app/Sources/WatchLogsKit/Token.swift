import Foundation

/// A 256-bit bearer token. Minted by the App, stored in the macOS Keychain on the
/// App side and in `chrome.storage.local` on the Extension side. No expiry; the
/// only way it changes is the manual "regenerate" action (issue #26).
public struct Token: Equatable, Sendable {
    /// Raw 32 bytes.
    public let raw: Data

    /// Wire / pairing-string representation: standard base64 of the raw bytes.
    public var base64: String { raw.base64EncodedString() }

    public init(raw: Data) {
        precondition(raw.count == Token.byteCount, "a token is \(Token.byteCount) bytes")
        self.raw = raw
    }

    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count == Token.byteCount else {
            return nil
        }
        self.raw = data
    }

    public static let byteCount = 32

    /// A fresh cryptographically-random token.
    public static func generate() -> Token {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = generator.next()
        }
        return Token(raw: Data(bytes))
    }
}

/// Constant-time equality over two byte buffers. Used to compare the presented
/// bearer against the real token so a caller can't probe it a byte at a time.
///
/// The comparison is constant-time in the *content* once the lengths match. Token
/// length is fixed and public, so a length mismatch returning early leaks nothing.
public func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (a, b) in zip(lhs, rhs) {
        difference |= a ^ b
    }
    return difference == 0
}
