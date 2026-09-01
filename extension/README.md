# WatchLogs extension

A Chromium **unpacked** extension. It watches every `<video>` / `<audio>` it can
see, records what they do as raw Events, and Flushes them to the WatchLogs
menubar app over loopback. It computes nothing: no Segments, no Watched time,
no "background" label — those are all the App's job (see `CONTEXT.md`).

## Load it

1. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → pick
   this `extension/` directory.
2. Open the WatchLogs menubar app, choose **Copy Pairing String**.
3. Open the extension's **Options** (or the toolbar popup → *Open pairing
   settings*), paste, click **Pair**.
4. Play a video anywhere. "Watched today" in the menubar should start climbing
   within about ten seconds.

The pairing string lives in `chrome.storage.local` — never in a bundled file.

## How the two halves split the work

| | page helper (`content.js`) | background worker (`background.js`) |
|---|---|---|
| runs | in **every frame** of every page | only when something wakes it |
| owns | Event capture, `viewId`, `seq`, the 5s `sample` timer, the on-disk buffer | the POST, the Ack, the prune, the pairing string |
| dies | with its frame | after each Flush — it is meant to be evicted |

That split is the point: an evicted service worker costs a little latency, never
a lost Event. The page helper appends to the buffer whatever the worker is doing,
and a `chrome.alarms` sweep every 30 s revives the worker to drain a buffer that
nobody has nudged (a throttled tab, a tab that closed mid-Flush).

## The buffer

`chrome.storage.local`, one key per thing, so an append and a prune in two
different processes can never clobber each other:

```
wl:view:<viewId>          the View header + lastSeq + last sample   (written by the frame)
wl:evt:<viewId>:<seq>     one Event                                 (written by the frame)
wl:ack:<viewId>           the highest seq the App has taken         (written by the worker)
```

An Event is a whole key of its own, so the worker's prune (`storage.local.remove`
of the keys at or below `ackSeq`) can't swallow an append that landed during the
POST. The worker only ever deletes frame-owned keys for a View that is closed and
fully Ack'd — one nobody will write to again.

## Crash recovery

The worker keeps a run id in `chrome.storage.session`, which survives the worker
being evicted but not the browser closing or being killed. Finding no run id is
therefore the definition of a fresh browser run, and any View still marked `open`
in the on-disk buffer belongs to the run before it: those are closed with
`viewEnded` reason `crash-recovered`, stamped at their **last `sample`** rather
than "now". A page helper's first message is a `hello` the worker answers only
after recovery has finished, so a restored tab can't be mistaken for a crashed
one.

## Layout

| File | Role |
|---|---|
| `manifest.json` | MV3; `storage` + `alarms`, `http://127.0.0.1/*` host permission (the CORS exemption), content script in all frames |
| `content.js` | page helper: media events → raw Events, the 5s timer, write-through to the buffer |
| `background.js` | worker: `POST /v1/flush`, Ack → prune, 30s sweep, crash recovery, pairing |
| `src/capture.js` | pure: `initSession` / `apply` / `buildFlush` — the capture seam, lifted from `prototypes/message-schema/` |
| `src/buffer.js` | pure: the key schema above, rehydrate, prune plan |
| `src/identify.js` | pure: Service, video id source, `embedded`, `contentFormat`, `mediaSession` metadata |
| `src/ids.js` | pure: uuidv4 and SHA-1, both usable on a plain `http://` page |
| `src/pairing.js` | pure: parse / encode the base64 pairing string |
| `src/flush.js` | pure: validate the Ack, decide accept / re-pair / retry |
| `src/state.js` | pure: connection-state reducer + one-line summary |
| `options.html` / `options.js` | paste + pair, pings `/v1/ping` before storing |
| `popup.html` / `popup.js` | shows the current connection line |

Content scripts can't be ES modules, so `content.js` pulls the `src/` modules in
with a dynamic `import()` of their extension URLs — that is what
`web_accessible_resources` is for in the manifest.

## Test

```
npm test                     # node --test over the pure modules and the round trip
node scripts/sample-flush.mjs   # print one Flush the way capture really builds it
```

`test/roundtrip.test.js` drives a scripted browser run — page helper, buffer,
worker, App — through the real modules with only storage and the network faked.
`scripts/sample-flush.mjs` generates the fixture the App's
`ExtensionCaptureTests` ingests, so the two languages are tested against the same
bytes; `test/fixture.test.js` fails if the committed fixture drifts.

The DOM wiring in `content.js` and the `chrome.*` calls in `background.js` are
exercised by loading the unpacked extension against a running App (manual QA
above).

## Known limits of this slice

- **Every media element counts.** With no per-Service Adapter yet, a decorative
  autoplaying `<video>` in a page banner opens a View like any other player.
  Adapters (a later slice) are what tell a real video from page furniture.
- **Metadata is `mediaSession` and best-effort only.** The Service is the bare
  hostname and the video id is `sha1:` of the normalised URL.
- **`tab-closed` is reported as `nav`.** A frame can't tell the two apart on the
  way out; the App treats both as "the View ended here".
- **Firefox is slice 8.** This is `chrome.*` and an MV3 service worker.
