import Foundation

/// A parsed HTTP/1.1 request head (everything before the body).
struct RequestHead: Equatable {
    var method: String
    /// Path only; any `?query` is dropped (none of our routes use one).
    var path: String
    /// Header names lower-cased; repeated headers joined with ", ".
    var headers: [String: String]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum HTTPParseError: Error, Equatable {
    case malformedRequestLine
    case unsupportedHTTPVersion
    case headerTooLarge
    case malformedHeader
}

enum HTTPRequestParser {
    /// Try to parse the head from `buffer`.
    ///
    /// - Returns: `(head, bodyOffset)` once the full `\r\n\r\n` terminator is
    ///   present, where `bodyOffset` is the index in `buffer` where the body
    ///   begins; `nil` if more bytes are needed.
    /// - Throws: `HTTPParseError` if what has arrived is already invalid, or if
    ///   the head exceeds `headerSectionCap` without terminating.
    static func parseHead(from buffer: Data, headerSectionCap: Int) throws -> (head: RequestHead, bodyOffset: Int)? {
        guard let terminatorStart = firstIndexOfCRLFCRLF(in: buffer) else {
            if buffer.count > headerSectionCap { throw HTTPParseError.headerTooLarge }
            return nil
        }

        let headData = buffer[buffer.startIndex..<terminatorStart]
        guard let headText = String(data: headData, encoding: .utf8) else {
            throw HTTPParseError.malformedHeader
        }

        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw HTTPParseError.malformedRequestLine }

        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw HTTPParseError.malformedRequestLine }
        let method = String(parts[0])
        let target = String(parts[1])
        let version = String(parts[2])
        guard method.allSatisfy({ $0.isLetter }), !method.isEmpty else {
            throw HTTPParseError.malformedRequestLine
        }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            throw HTTPParseError.unsupportedHTTPVersion
        }

        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])

        var headers: [String: String] = [:]
        for line in lines {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPParseError.malformedHeader
            }
            let name = line[line.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw HTTPParseError.malformedHeader }
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let terminatorEnd = buffer.index(terminatorStart, offsetBy: 4)
        let bodyOffset = buffer.distance(from: buffer.startIndex, to: terminatorEnd)
        return (RequestHead(method: method, path: path, headers: headers), bodyOffset)
    }

    /// Index of the first `\r\n\r\n` byte in `data`, or `nil`.
    private static func firstIndexOfCRLFCRLF(in data: Data) -> Data.Index? {
        guard data.count >= 4 else { return nil }
        let bytes = Array(data)
        var i = 0
        while i <= bytes.count - 4 {
            if bytes[i] == 0x0D, bytes[i + 1] == 0x0A, bytes[i + 2] == 0x0D, bytes[i + 3] == 0x0A {
                return data.index(data.startIndex, offsetBy: i)
            }
            i += 1
        }
        return nil
    }
}

/// A response to serialise back onto the connection. Always `Connection: close`;
/// the server answers one request per connection.
struct HTTPResponse {
    var status: Int
    var headers: [(name: String, value: String)]
    var body: Data

    init(status: Int, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json(status: Int, _ object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(
            status: status,
            headers: [("Content-Type", "application/json")],
            body: body
        )
    }

    static func json(status: Int, raw body: Data) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "application/json")], body: body)
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        var merged = headers
        merged.append(("Content-Length", String(body.count)))
        merged.append(("Connection", "close"))
        for header in merged {
            head += "\(header.name): \(header.value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
