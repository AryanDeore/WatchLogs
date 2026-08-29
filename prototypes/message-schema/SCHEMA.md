# Flush message schema (v1)

The exact wire format the Extension POSTs to the App. Resolved by wayfinder ticket
[#2](https://github.com/AryanDeore/WatchLogs/issues/2). This is the deliverable asset:
a concrete full-Flush example plus a field reference. The interactive prototype that
this was reacted to against is `index.html` in this directory.

- **Method / path:** `POST http://127.0.0.1:<port>/flush` (port + auth are ticket #3's problem)
- **Content-Type:** `application/json`
- **Cadence:** every 5s while any View plays, and once on media-end / View-end. A Flush
  with `views: []` is a valid heartbeat.

---

## Concrete example — one Flush carrying two Views

A user watched a YouTube video, then the tab auto-played the next one. The first View
(`view-9f2a…`) has ended (`video-changed`); the second (`view-3b7c…`) is still open,
was just backgrounded, and had its speed bumped to 2×.

```json
{
  "schemaVersion": 1,
  "flushId": "f1e2d3c4-5b6a-4c7d-8e9f-0a1b2c3d4e5f",
  "sentAt": 1788026435000,
  "agent": {
    "extInstanceId": "ext-inst-7f3a9c21",
    "extVersion": "0.1.0",
    "browser": "chrome",
    "os": "macOS 15.6"
  },
  "views": [
    {
      "viewId": "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40",
      "service": "youtube",
      "contentFormat": "standard",
      "embedded": false,
      "videoId": "dQw4w9WgXcQ",
      "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "title": "Never Gonna Give You Up",
      "author": "Rick Astley",
      "artworkUrl": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
      "durationSec": 213,
      "metadataSource": "adapter",
      "adapterId": "youtube",
      "tabId": 41,
      "startedAt": 1788026400000,
      "open": false,
      "previousViewId": null,
      "events": [
        { "seq": 1, "type": "mediaFound",     "t": 1788026400000, "pos": 0 },
        { "seq": 2, "type": "metadataChange", "t": 1788026400500, "pos": 0,
          "changed": { "title": "Never Gonna Give You Up", "author": "Rick Astley",
                       "artworkUrl": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
                       "durationSec": 213 } },
        { "seq": 3, "type": "play",    "t": 1788026401000, "pos": 0 },
        { "seq": 4, "type": "sample",  "t": 1788026406000, "pos": 5.0,  "playing": true, "visible": true },
        { "seq": 5, "type": "sample",  "t": 1788026411000, "pos": 10.0, "playing": true, "visible": true },
        { "seq": 6, "type": "seeked",  "t": 1788026413000, "pos": 45.2, "from": 10.6, "to": 45.2 },
        { "seq": 7, "type": "sample",  "t": 1788026416000, "pos": 48.2, "playing": true, "visible": true },
        { "seq": 8, "type": "viewEnded", "t": 1788026418000, "pos": 50.2, "reason": "video-changed" }
      ]
    },
    {
      "viewId": "view-3b7c88e1-9a02-4f31-8d77-2e5b4c9a1f66",
      "service": "youtube",
      "contentFormat": "standard",
      "embedded": false,
      "videoId": "kJQP7kiw5Fk",
      "url": "https://www.youtube.com/watch?v=kJQP7kiw5Fk",
      "title": "Luis Fonsi - Despacito ft. Daddy Yankee",
      "author": "Luis Fonsi",
      "artworkUrl": "https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg",
      "durationSec": 282,
      "metadataSource": "adapter",
      "adapterId": "youtube",
      "tabId": 41,
      "startedAt": 1788026418000,
      "open": true,
      "previousViewId": "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40",
      "events": [
        { "seq": 1, "type": "mediaFound", "t": 1788026418000, "pos": 0 },
        { "seq": 2, "type": "play",       "t": 1788026419000, "pos": 0 },
        { "seq": 3, "type": "sample",     "t": 1788026424000, "pos": 5.0,  "playing": true, "visible": true },
        { "seq": 4, "type": "hidden",     "t": 1788026426000, "pos": 7.0 },
        { "seq": 5, "type": "sample",     "t": 1788026429000, "pos": 10.0, "playing": true, "visible": false },
        { "seq": 6, "type": "ratechange", "t": 1788026431000, "pos": 12.0, "rate": 2.0 },
        { "seq": 7, "type": "sample",     "t": 1788026434000, "pos": 18.0, "playing": true, "visible": false }
      ]
    }
  ]
}
```

### Ack response

```json
{
  "flushId": "f1e2d3c4-5b6a-4c7d-8e9f-0a1b2c3d4e5f",
  "accepted": true,
  "views": [
    { "viewId": "view-9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40", "ackSeq": 8 },
    { "viewId": "view-3b7c88e1-9a02-4f31-8d77-2e5b4c9a1f66", "ackSeq": 7 }
  ],
  "serverTime": 1788026435004
}
```

The Extension prunes every Event with `seq <= ackSeq` for that View from its on-disk
buffer. A View reappears in a later Flush only if it has Events with a higher `seq`.
Re-sending a Flush whose Ack was lost reuses the same `flushId`; the App replays the
stored Ack and ignores the duplicate Events.

---

## Field reference

### Envelope

| Field | Type | Req | Notes |
|---|---|---|---|
| `schemaVersion` | int | yes | `1`. Bumped only on a breaking change. Unknown value → App responds `415` + `{ "error": "schemaVersion" }`; it never guesses. |
| `flushId` | string (uuidv4) | yes | New per POST attempt; **reused** verbatim on a retry after a lost Ack. App dedups on it. |
| `sentAt` | int (epoch ms) | yes | Extension wall clock when the body was built. App compares against its receipt time to measure skew. |
| `agent` | object | yes | `{ extInstanceId, extVersion, browser, os }`. `extInstanceId` is minted once at install, stable across restarts — distinguishes two browsers pointed at one App. |
| `views` | View[] | yes | May be empty. Never null. |

### View

| Field | Type | Req | Notes |
|---|---|---|---|
| `viewId` | string (uuidv4) | yes | Minted by the Extension when the View starts. Stable across Flushes — the App's correlation + idempotency key. |
| `service` | string | yes | Adapter Service id (`youtube`, `netflix`) or, with no Adapter, the bare hostname. |
| `contentFormat` | enum | yes | `short` \| `standard` \| `live`. Best guess at start; a later correction is a `metadataChange`. |
| `embedded` | bool | yes | true when the player is on a third-party page, not the Service's own site. |
| `videoId` | string | yes | Service-native id. For a no-Adapter site, `sha1:` of the normalised URL. |
| `url` | string | yes | Page URL, query stripped except Service-significant params (e.g. YouTube `v`). |
| `title` | string \| null | no | null until metadata resolves. Header always holds the latest known value. |
| `author` | string \| null | no | Channel / uploader / studio. |
| `artworkUrl` | string \| null | no | Thumbnail / poster. |
| `durationSec` | number \| null | no | Float seconds. null for live or not-yet-known. |
| `metadataSource` | enum \| null | no | `mediaSession` \| `adapter` \| `generic`. null before any metadata. |
| `adapterId` | string \| null | no | Which Adapter produced metadata; null when `generic`. |
| `tabId` | int | yes | Browser tab id. Not unique over time — `viewId` is the stable key. |
| `startedAt` | int (epoch ms) | yes | Wall clock of the first `mediaFound`. |
| `open` | bool | yes | Convenience mirror: `false` ⟺ this batch carries the View's `viewEnded`. Kept so the App has one unambiguous liveness flag without scanning events. |
| `previousViewId` | string \| null | no | Set when this View began because the tab's video id changed. Links the chain; null otherwise. |
| `events` | Event[] | yes | Only Events with `seq` above the last Ack'd value for this View, ordered by `seq`. |

### Event — common envelope

| Field | Type | Req | Notes |
|---|---|---|---|
| `seq` | int | yes | Monotonic per View from 1. Ordering + dedup key for overlapping re-sends. |
| `type` | enum | yes | See below. |
| `t` | int (epoch ms) | yes | Extension wall clock at capture. |
| `pos` | number \| null | no | Media position, float seconds (3 dp). null where the player has no position (pre-play; live with no DVR). |

### Event — type-specific fields

| `type` | Extra fields | Meaning |
|---|---|---|
| `mediaFound` | — | A media element with a resolvable id appeared. Starts the View. |
| `play` | — | Playback began / resumed. |
| `pause` | — | Playback paused (user, buffering stall, or tab throttle). |
| `seeked` | `from`, `to` (number, sec) | Position jumped. `from` is the pre-seek position. |
| `ratechange` | `rate` (number) | Playback speed changed. Watched time still accrues in wall-clock, not media time. |
| `visible` / `hidden` | — | Tab entered / left the foreground (`visibilitychange`). |
| `pipEnter` / `pipLeave` | — | Picture-in-Picture toggled. PiP still counts as Watched. |
| `metadataChange` | `changed` (object: field → new value) | One or more View header fields resolved or changed. The header also carries the new values. |
| `sample` | `playing` (bool), `visible` (bool) | 5s heartbeat. Bounds data loss; lets the App spot a missed `pause` / `hidden`. `pos` is the sampled position. |
| `ended` | — | Media reached its natural end. The View may still get more Events (a replay). |
| `viewEnded` | `reason` (enum) | `nav` \| `tab-closed` \| `video-changed` \| `crash-recovered`. Last Event of the View. For `crash-recovered`, `t` / `pos` are the **last `sample`**, not "now". |

---

## Resolved decisions (ticket #2)

1. **Time is epoch-ms int** everywhere (`t`, `sentAt`, `startedAt`) — not ISO strings. Smaller, directly comparable, skew correction is arithmetic.
2. **Position is float seconds**, 3 dp — matches `HTMLMediaElement.currentTime`.
3. **The Extension mints all ids** (`viewId`, `flushId`, both uuidv4). The App never generates ids; it correlates on `viewId` and dedups Flushes on `flushId`.
4. **`open` is kept** as a convenience field even though it is derivable from the presence of a `viewEnded` event in the batch.
5. **No standalone `videoChange` event.** A new video id in one tab = old View closes with `viewEnded` reason `video-changed`; the new View starts with `previousViewId` set.
6. **`sample` cadence = Flush cadence (5s)** for v1. Ticket [#6](https://github.com/AryanDeore/WatchLogs/issues/6) may decouple it (e.g. 1s samples inside a 5s Flush) if Segment math needs finer loss bounds; the schema already allows any cadence.
7. **Idempotency is two-layer:** the App stores seen `flushId`s and replays the Ack on a duplicate; within a View, `seq` lets a re-send that overlaps a prior partial success dedup cleanly. The Ack returns the highest `seq` accepted per View (`ackSeq`).
8. **Ack shape:** `{ flushId, accepted: true, views: [{ viewId, ackSeq }], serverTime }`. Rejection is an HTTP 4xx with `{ error }` — there is no body-level per-View partial-accept.
9. **Metadata lives in two places:** the View header always holds the latest known values, *and* a `metadataChange` event records the moment each changed (kept for the raw log).
10. **Zero computed fields on the wire.** The Extension reports raw facts only (`hidden`, `sample.visible`, `ratechange`, …). Derived concepts — Background audio, Segments, Watched time — are entirely the App's job.

### Schema versioning

A single top-level `schemaVersion` integer. Incremented only on a change that an
existing App could not parse safely (a removed/renamed field, a changed type, a
removed event type). Additive changes — a new optional field, a new event `type`, a
new `viewEnded.reason` — do **not** bump it; an older App ignores unknown fields and
must treat an unknown event `type` or `reason` as an opaque, recorded-but-uninterpreted
Event. On a version it does not recognise the App rejects the whole Flush with `415`
so the Extension keeps the data buffered rather than dropping it.
