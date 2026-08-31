import Foundation

/// A deliberately dumb HTTP/1.1 client for the loopback-server tests. Raw sockets
/// so a test can send an exact byte sequence (a bad token with a huge body, a
/// truncated body, overlapping requests) and read whatever the server sends back
/// even when it closes the connection early.
struct RawHTTPClient {
    let host: String
    let port: Int

    struct Response {
        var status: Int
        var headers: [String: String] // lower-cased names
        var body: Data

        func header(_ name: String) -> String? { headers[name.lowercased()] }
        var bodyString: String { String(decoding: body, as: UTF8.self) }
        func json() -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    enum ClientError: Error {
        case connectFailed(Int32)
        case sendFailed
        case noResponse
        case malformedResponse
    }

    /// Send `method path` with the given headers and body; return the parsed
    /// response. `extraHeaders` values are sent verbatim.
    func send(
        method: String,
        path: String,
        headers extraHeaders: [String: String] = [:],
        body: Data = Data(),
        overrideContentLength: Int? = nil,
        includeContentLength: Bool = true
    ) throws -> Response {
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: \(host):\(port)\r\n"
        for (name, value) in extraHeaders {
            request += "\(name): \(value)\r\n"
        }
        if includeContentLength {
            request += "Content-Length: \(overrideContentLength ?? body.count)\r\n"
        }
        request += "Connection: close\r\n\r\n"

        var payload = Data(request.utf8)
        payload.append(body)
        let raw = try roundTrip(payload)
        return try parse(raw)
    }

    /// Lower-level: send exact bytes, return exact bytes.
    func roundTrip(_ payload: Data) throws -> Data {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.connectFailed(errno) }
        defer { close(fd) }

        // The server answers some requests before reading their body — a 413 on
        // an oversized one — and closes. Without this, the write below raises
        // SIGPIPE and takes the whole test process down with it; with it, the
        // write just fails and we can go read the response the server did send.
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &addr.sin_addr)

        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { throw ClientError.connectFailed(errno) }

        var toSend = payload
        while !toSend.isEmpty {
            let sent = toSend.withUnsafeBytes { buffer in
                write(fd, buffer.baseAddress, buffer.count)
            }
            if sent > 0 {
                toSend.removeFirst(sent)
                continue
            }
            // The peer hung up mid-write: it has already decided about this
            // request. Whatever it replied is still in our receive buffer.
            if sent < 0, errno == EPIPE || errno == ECONNRESET { break }
            throw ClientError.sendFailed
        }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let read = chunk.withUnsafeMutableBytes { pointer in
                Foundation.read(fd, pointer.baseAddress, pointer.count)
            }
            if read > 0 {
                response.append(contentsOf: chunk[0..<read])
            } else {
                break
            }
        }
        guard !response.isEmpty else { throw ClientError.noResponse }
        return response
    }

    private func parse(_ raw: Data) throws -> Response {
        guard let terminator = raw.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            throw ClientError.malformedResponse
        }
        let headText = String(decoding: raw[raw.startIndex..<terminator.lowerBound], as: UTF8.self)
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ClientError.malformedResponse }

        let statusLine = lines.removeFirst().split(separator: " ")
        guard statusLine.count >= 2, let status = Int(statusLine[1]) else {
            throw ClientError.malformedResponse
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let body = Data(raw[terminator.upperBound...])
        return Response(status: status, headers: headers, body: body)
    }
}
