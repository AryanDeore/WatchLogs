import Foundation
import Testing
@testable import WatchLogsKit

@Suite("Pairing string codec")
struct PairingStringTests {
    @Test("round-trips {host, port, token}")
    func roundTrip() throws {
        let original = Pairing(host: "127.0.0.1", port: 48920, token: Token.generate().base64)
        let decoded = try PairingCodec.decode(PairingCodec.encode(original))
        #expect(decoded == original)
    }

    @Test("the pairing string is base64 of a JSON object")
    func shapeIsBase64JSON() throws {
        let pairing = Pairing(host: "127.0.0.1", port: 49001, token: "dG9rZW4=")
        let string = PairingCodec.encode(pairing)
        let data = try #require(Data(base64Encoded: string))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["host"] as? String == "127.0.0.1")
        #expect(json["port"] as? Int == 49001)
        #expect(json["token"] as? String == "dG9rZW4=")
    }

    @Test("rejects a non-base64 string")
    func rejectsNonBase64() {
        #expect(throws: PairingStringError.notBase64) {
            _ = try PairingCodec.decode("not base64 @@@@")
        }
    }

    @Test("rejects base64 that is not a JSON object")
    func rejectsNonJSON() {
        let notJSON = Data("hello world".utf8).base64EncodedString()
        #expect(throws: PairingStringError.notJSON) {
            _ = try PairingCodec.decode(notJSON)
        }
    }

    @Test("rejects a missing field")
    func rejectsMissingField() {
        let missingToken = Data(#"{"host":"127.0.0.1","port":48920}"#.utf8).base64EncodedString()
        #expect(throws: PairingStringError.missingField("token")) {
            _ = try PairingCodec.decode(missingToken)
        }
    }

    @Test("rejects a fractional or out-of-range port")
    func rejectsBadPort() {
        let fractional = Data(#"{"host":"h","port":80.5,"token":"t"}"#.utf8).base64EncodedString()
        #expect(throws: PairingStringError.invalidPort) {
            _ = try PairingCodec.decode(fractional)
        }
        let huge = Data(#"{"host":"h","port":99999,"token":"t"}"#.utf8).base64EncodedString()
        #expect(throws: PairingStringError.invalidPort) {
            _ = try PairingCodec.decode(huge)
        }
    }

    @Test("tolerates surrounding whitespace")
    func toleratesWhitespace() throws {
        let pairing = Pairing(host: "127.0.0.1", port: 48920, token: "dG9rZW4=")
        let padded = "  \n" + PairingCodec.encode(pairing) + "\n  "
        #expect(try PairingCodec.decode(padded) == pairing)
    }
}
