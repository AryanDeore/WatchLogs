import Foundation

/// The `{host, port, token}` triple the App shows in Settings and the user pastes
/// into the Extension once. Encoded as base64 of its JSON form (issue #26).
public struct Pairing: Equatable, Sendable {
    public var host: String
    public var port: Int
    /// base64 of the 256-bit token.
    public var token: String

    public init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
    }
}

public enum PairingStringError: Error, Equatable {
    case notBase64
    case notJSON
    case missingField(String)
    case invalidPort
}

/// `Pairing` <-> pairing string.
///
/// The string is `base64( utf8( {"host":…,"port":…,"token":…} ) )` with sorted
/// keys so the encoding is deterministic and round-trips exactly.
public enum PairingCodec {
    public static func encode(_ pairing: Pairing) -> String {
        // Built by hand (not JSONEncoder) so key order and spacing are fixed and
        // the round-trip is byte-stable regardless of platform encoder quirks.
        let object = "{\"host\":\(jsonString(pairing.host)),\"port\":\(pairing.port),\"token\":\(jsonString(pairing.token))}"
        return Data(object.utf8).base64EncodedString()
    }

    public static func decode(_ string: String) throws -> Pairing {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else {
            throw PairingStringError.notBase64
        }
        guard
            let any = try? JSONSerialization.jsonObject(with: data),
            let object = any as? [String: Any]
        else {
            throw PairingStringError.notJSON
        }
        guard let host = object["host"] as? String else {
            throw PairingStringError.missingField("host")
        }
        guard object["token"] is String, let token = object["token"] as? String else {
            throw PairingStringError.missingField("token")
        }
        guard let portValue = object["port"] else {
            throw PairingStringError.missingField("port")
        }
        guard let port = portAsInt(portValue), (1...65535).contains(port) else {
            throw PairingStringError.invalidPort
        }
        return Pairing(host: host, port: port, token: token)
    }

    private static func portAsInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            // Reject a fractional port like 8080.5.
            let intValue = number.intValue
            return Double(intValue) == number.doubleValue ? intValue : nil
        }
        return nil
    }

    private static func jsonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
