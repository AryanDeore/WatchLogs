# WatchLogs App

The macOS menubar App: loopback HTTP receiver, SQLite storage, Segment
computation, and the menubar UI in one process.

Built in tracer-bullet slices:

- **Slice 1 (#26)** — loopback handshake: server, bearer auth, pairing string,
  status line.
- **Slice 2 (#19)** — one video's Event log becomes Watched time: `raw_events`,
  the Segment state machine, `totals(range)`, and "Watched today".

## Run

```
swift run WatchLogs
```

A menubar item appears (`Watch·Logs ○` / `●`). Its menu shows **Watched today**,
the connection status line, **Pairing String…** (the base64 string with a Copy
button) and **Regenerate Token**. The token lives in the macOS Keychain
(`com.watchlogs.app` / `loopback-token`); the database lives in
`~/Library/Application Support/WatchLogs/watchlogs.sqlite`.

To drive it by hand without a browser:

```
./scripts/fake-extension.sh              # heartbeats only — turns the status line green
./scripts/fake-session.sh 30             # one 30 s View — "Watched today" climbs by 30 s
./scripts/fake-session.sh 30 48920 --background   # 30 s in a hidden tab — Watched today does not move
```

Both read the token from the Keychain, or from `WATCHLOGS_TOKEN` if set.

## Wire surface

| Route | Auth | Behaviour |
|---|---|---|
| `GET /v1/ping` | none | `200 {app, version, contract:"v1"}` |
| `POST /v1/flush` | `Authorization: Bearer <token>`, constant-time, **before the body is read** | `200` Ack `{flushId, accepted:true, views:[{viewId, ackSeq}], serverTime}`; `401` bad/missing token; `413` body > 1 MiB; `415 {error:"schemaVersion"}` unknown top-level `schemaVersion` (stores nothing); `400` unparseable or a View missing a required field (stores nothing); `500 {error:"storage"}` valid but unstorable, so the Extension keeps the batch |
| `OPTIONS /v1/flush` | none | `204`, **no** `Access-Control-Allow-*` headers |

Binds `127.0.0.1:48920`, rolling forward to the next free port on collision. One
request in flight at a time. JSON only, plain HTTP.

Delivery is at-least-once (ADR 0002). A Flush resent with the same `flushId`
stores nothing and replays the first delivery's Ack verbatim, `serverTime` and
all. A batch that overlaps an earlier one under a *new* `flushId` is stored — the
log is append-only and may hold the same Event twice — and de-duplicated on
`(viewId, seq)` when Segments are recomputed. `ackSeq` is the highest `seq` the
log holds for that View, so the Extension prunes everything the App has.

## From Events to Watched time

`SegmentComputer` is a pure function: one View's whole Event log in, its Segments
out. It re-runs over the entire log every time new Events land for that View, so
a retry, an out-of-order batch, or a crash-recovery Flush hours later all land on
the same answer a single pass would (ADR 0003).

The machine tracks three facts — `playing`, `visible`, `pip` — and keeps one
Segment open whenever `playing` holds. Foreground (`visible OR pip`) decides the
open Segment's `kind`: losing the foreground does not stop the clock, it closes
the `watched` Segment and opens a `background` one at the same instant. A
`seeked` splits the same way, closing at `from` and reopening at `to`, so each
Segment covers one continuous media range. `ratechange`, `metadataChange` and
`mediaFound` change nothing — Watched time is wall-clock, so 60 real seconds at
2× is 60 seconds.

Boundaries that must be *inferred* — a heartbeat reveals a `pause` that never
arrived — fall at the last instant that positively confirmed every condition,
never at the heartbeat that revealed the change. The uncertain gap counts for
neither kind. A `crash-recovered` tail closes at the last `sample`. Segments
under 1000 ms are discarded after seek-splitting, and an open View's trailing
Segment is `provisional` and replaced on every recompute.

Two readings worth knowing, both narrower than they look in ADR 0003:

- **The PiP toggles change `kind`, they do not open or close a span of
  playback.** That is what keeps "PiP still counts as Watched" true for a video
  playing in a hidden tab.
- **Only a `sample` confirms.** An explicit `play` vouches for `playing` at its
  own timestamp but says nothing about visibility, so the heartbeat is what moves
  the last-confirmed instant forward.

## Reading the totals

`totals(range)` sums `watched` and `background` milliseconds over a half-open
window, clipping each Segment to it at read time — Segments are stored whole and
never mutated. Sums stay in milliseconds and round to whole seconds once, at the
end.

**Day flex is not in this slice.** `DateRange.day(containing:)` is a naive local
calendar day, so a session running 23:00 → 02:00 splits across two days.
The activity-flexed Day of ADR 0001 replaces it in slice 4.

## Layout

| Target | Contents |
|---|---|
| `WatchLogsKit` | `LoopbackServer` (NWListener), `HTTPMessage` (parser), `Ingest` + `FlushEnvelope` + `RawEvent`, `SegmentComputer` + `Segment`, `EventStore` + `SQLite`, `ReadModel` (`DateRange`, `Totals`), `PairingCodec`, `Token` + `TokenStore` / `KeychainTokenStore`, `MenubarStatus` + `WatchedTimeLine`, `Clock`, `LoopbackTransport` (wires them) |
| `WatchLogs` | the AppKit `NSStatusItem` executable |
| `WatchLogsKitTests` | Swift Testing. Seam 1 (`WatchedTimeTests`) drives the real server over a raw socket and asserts on read-model totals; `SegmentComputationTests` drives the pure state machine directly |

## Storage

SQLite, one connection, all access serialised. Recording a Flush and recomputing
the Views it touched happen in one transaction.

| Table | Notes |
|---|---|
| `flushes` | `flush_id` → the Ack that was returned, for replay |
| `views` | one row per View; the header mirrors the latest known metadata |
| `raw_events` | append-only; may hold the same `(view_id, seq)` twice; consumers de-duplicate |
| `segments` | re-derivable, replaced wholesale per View on every recompute |

`rolled_day` / `rollup_slice` (ADR 0004) arrive with the rollup slice.

## Test

```
swift test
```
