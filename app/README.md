# WatchLogs App — loopback handshake (issue #26)

The macOS menubar App's tracer-bullet slice: the loopback HTTP server, bearer
auth, pairing string, and a menubar status line. No SQLite, no Segment
computation yet.

## Run

```
swift run WatchLogs
```

A menubar item appears (`Watch·Logs ○` / `●`). Its menu shows the single status
line, plus **Pairing String…** (displays the base64 string with a Copy button)
and **Regenerate Token**. The token lives in the macOS Keychain
(`com.watchlogs.app` / `loopback-token`).

## Wire surface

| Route | Auth | Behaviour |
|---|---|---|
| `GET /v1/ping` | none | `200 {app, version, contract:"v1"}` |
| `POST /v1/flush` | `Authorization: Bearer <token>`, constant-time, **before the body is read** | `200` Ack `{flushId, accepted:true, views:[], serverTime}`; `401` bad/missing token; `413` body > 1 MiB; `415 {error:"schemaVersion"}` unknown top-level `schemaVersion` (stores nothing); `400` unparseable |
| `OPTIONS /v1/flush` | none | `204`, **no** `Access-Control-Allow-*` headers |

Binds `127.0.0.1:48920`, rolling forward to the next free port on collision. One
request in flight at a time. JSON only, plain HTTP. Delivery is at-least-once
(ADR 0002): the App keeps no memory of Flushes it has seen, so a resent Flush is
simply acked again.

## Layout

| Target | Contents |
|---|---|
| `WatchLogsKit` | `LoopbackServer` (NWListener), `HTTPMessage` (parser), `Ingest` + `FlushEnvelope`, `PairingCodec`, `Token` + `TokenStore` / `KeychainTokenStore`, `MenubarStatus`, `Clock`, `LoopbackTransport` (wires them) |
| `WatchLogs` | the AppKit `NSStatusItem` executable |
| `WatchLogsKitTests` | Swift Testing; drives the real server over a raw socket (`RawHTTPClient`) |

## Test

```
swift test
```
