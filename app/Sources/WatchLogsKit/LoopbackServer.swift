import Foundation
import Network

/// The App's local HTTP server. Binds `127.0.0.1` on a fixed default port and
/// rolls forward to the next free port on collision. Wire surface is exactly
/// `GET /v1/ping` and `POST /v1/flush`, JSON only, plain HTTP (issue #26).
///
/// All connections share one serial dispatch queue and ingest is synchronous and
/// lock-guarded, so there is genuinely one request in flight at a time.
public final class LoopbackServer: @unchecked Sendable {
    public struct Config: Sendable {
        public var appName: String
        public var version: String
        public var contract: String
        public var defaultPort: Int
        public var portRollAttempts: Int
        public var maxBodyBytes: Int
        public var headerSectionCap: Int

        public init(
            version: String,
            appName: String = LoopbackDefaults.appName,
            contract: String = LoopbackDefaults.contract,
            defaultPort: Int = LoopbackDefaults.port,
            portRollAttempts: Int = LoopbackDefaults.portRollAttempts,
            maxBodyBytes: Int = LoopbackDefaults.maxBodyBytes,
            headerSectionCap: Int = LoopbackDefaults.headerSectionCap
        ) {
            self.version = version
            self.appName = appName
            self.contract = contract
            self.defaultPort = defaultPort
            self.portRollAttempts = portRollAttempts
            self.maxBodyBytes = maxBodyBytes
            self.headerSectionCap = headerSectionCap
        }
    }

    public enum StartError: Error, Equatable {
        case noFreePort(triedFrom: Int, attempts: Int)
    }

    private let config: Config
    private let tokenProvider: @Sendable () -> Data
    private let ingest: Ingest
    private let queue = DispatchQueue(label: "com.watchlogs.loopback")

    private let lock = NSLock()
    private var listener: NWListener?
    private var _boundPort: Int?
    private var _bodyBytesRead = 0

    public init(config: Config, tokenProvider: @escaping @Sendable () -> Data, ingest: Ingest) {
        self.config = config
        self.tokenProvider = tokenProvider
        self.ingest = ingest
    }

    /// The port actually bound, once `start()` has succeeded.
    public var boundPort: Int? {
        lock.lock(); defer { lock.unlock() }
        return _boundPort
    }

    /// Total request-body bytes the server has pulled off the socket for
    /// processing. A request rejected before its body (bad token, oversized
    /// `Content-Length`) contributes nothing. Test observability.
    public var bodyBytesRead: Int {
        lock.lock(); defer { lock.unlock() }
        return _bodyBytesRead
    }

    public var maxObservedIngestConcurrency: Int { ingest.maxObservedConcurrency }

    public func start() throws {
        for offset in 0..<config.portRollAttempts {
            let port = config.defaultPort + offset
            if bind(port: port) {
                lock.lock(); _boundPort = port; lock.unlock()
                return
            }
        }
        throw StartError.noFreePort(triedFrom: config.defaultPort, attempts: config.portRollAttempts)
    }

    public func stop() {
        lock.lock()
        let current = listener
        listener = nil
        _boundPort = nil
        lock.unlock()
        current?.cancel()
    }

    // MARK: - Binding

    private func bind(port: Int) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(LoopbackDefaults.host), port: nwPort)
        parameters.allowLocalEndpointReuse = false

        guard let candidate = try? NWListener(using: parameters) else { return false }

        let ready = DispatchSemaphore(value: 0)
        let outcome = BindOutcome()
        candidate.stateUpdateHandler = { state in
            switch state {
            case .ready:
                outcome.set(true); ready.signal()
            case .failed, .cancelled:
                outcome.set(false); ready.signal()
            default:
                break
            }
        }
        candidate.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        candidate.start(queue: queue)

        if ready.wait(timeout: .now() + 3) == .timedOut || !outcome.value {
            candidate.cancel()
            return false
        }
        lock.lock(); listener = candidate; lock.unlock()
        return true
    }

    // MARK: - Connection lifecycle

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
    }

    private func receiveHead(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil { connection.cancel(); return }

            var accumulated = buffer
            if let data, !data.isEmpty { accumulated.append(data) }

            do {
                if let (head, bodyOffset) = try HTTPRequestParser.parseHead(
                    from: accumulated,
                    headerSectionCap: self.config.headerSectionCap
                ) {
                    let pending = Data(accumulated[(accumulated.startIndex + bodyOffset)...])
                    self.route(head: head, alreadyBuffered: pending, on: connection)
                } else if isComplete {
                    connection.cancel()
                } else {
                    self.receiveHead(on: connection, buffer: accumulated)
                }
            } catch {
                let tooLarge = (error as? HTTPParseError) == .headerTooLarge
                self.respond(
                    .json(status: tooLarge ? 431 : 400, ["error": tooLarge ? "header too large" : "bad request"]),
                    on: connection
                )
            }
        }
    }

    // MARK: - Routing

    private func route(head: RequestHead, alreadyBuffered: Data, on connection: NWConnection) {
        switch (head.method, head.path) {
        case ("OPTIONS", "/v1/flush"):
            // CORS preflight. 204, and deliberately no Access-Control-Allow-*
            // headers — a web page's fetch is meant to fail here.
            respond(HTTPResponse(status: 204), on: connection)

        case ("GET", "/v1/ping"):
            respond(.json(status: 200, [
                "app": config.appName,
                "version": config.version,
                "contract": config.contract,
            ]), on: connection)

        case ("POST", "/v1/flush"):
            guard isAuthorized(head) else {
                // Rejected before the body is read.
                respond(.json(status: 401, ["error": "unauthorized"]), on: connection)
                return
            }
            guard
                let lengthText = head.header("content-length"),
                let contentLength = Int(lengthText),
                contentLength >= 0
            else {
                respond(.json(status: 411, ["error": "length required"]), on: connection)
                return
            }
            guard contentLength <= config.maxBodyBytes else {
                respond(.json(status: 413, ["error": "too large"]), on: connection)
                return
            }
            readBody(on: connection, have: alreadyBuffered, need: contentLength) { [weak self] body in
                guard let self else { return }
                self.lock.lock(); self._bodyBytesRead += body.count; self.lock.unlock()

                switch self.ingest.handle(body: body) {
                case .accepted(let ack):
                    self.respond(.json(status: 200, raw: ack.jsonData()), on: connection)
                case .badRequest(let reason):
                    self.respond(.json(status: 400, ["error": reason]), on: connection)
                case .unsupportedSchemaVersion:
                    self.respond(.json(status: 415, ["error": "schemaVersion"]), on: connection)
                }
            }

        case (_, "/v1/flush"):
            respond(.json(status: 405, ["error": "method not allowed"]), on: connection)

        default:
            respond(.json(status: 404, ["error": "not found"]), on: connection)
        }
    }

    private func readBody(
        on connection: NWConnection,
        have: Data,
        need: Int,
        completion: @escaping @Sendable (Data) -> Void
    ) {
        if have.count >= need {
            completion(Data(have.prefix(need)))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil { connection.cancel(); return }

            var accumulated = have
            if let data { accumulated.append(data) }

            if accumulated.count >= need {
                completion(Data(accumulated.prefix(need)))
            } else if isComplete {
                self.respond(.json(status: 400, ["error": "truncated body"]), on: connection)
            } else {
                self.readBody(on: connection, have: accumulated, need: need, completion: completion)
            }
        }
    }

    // MARK: - Auth

    private func isAuthorized(_ head: RequestHead) -> Bool {
        let real = Data(tokenProvider().base64EncodedString().utf8)
        guard let value = head.header("authorization") else {
            _ = constantTimeEquals(real, real) // keep the failure path's timing shape similar
            return false
        }
        let scheme = "Bearer "
        guard value.hasPrefix(scheme) else { return false }
        let presented = Data(value.dropFirst(scheme.count).utf8)
        return constantTimeEquals(presented, real)
    }

    // MARK: - Response

    private func respond(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Thread-safe one-shot flag for the bind handshake.
private final class BindOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
