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

Reloading an unpacked extension (the ↻ on its card in `chrome://extensions`)
kills the content script in every tab that was already open — MV3 does not
re-inject it — so a tab you were using for manual QA before the reload will
look paired but silently capture nothing until you refresh it.

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
POST — a frame writes each `seq` once and only counts up, so an Ack'd key is one
nobody will write again. The View header is frame-owned and the worker deletes it
in one case only: a View that is closed and fully Ack'd (ADR 0005).

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
| `background.js` | worker: `POST /v1/flush`, Ack → prune, 30s sweep, crash + closed-tab recovery, pairing |
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

### content.js: the DOM layer

`content.js` is the one file `npm test` can't reach — it needs a real DOM and a
real `chrome.*`, which `node --test`'s pure-module world doesn't provide. It
gets its own suite instead:

```
npm run test:e2e
```

This drives the actual unpacked extension in a real Chromium
(`chromium.launchPersistentContext` + `--load-extension`, per
`test-e2e/extension.mjs`), against a stub App (`test-e2e/stub-server.mjs`)
bound to `127.0.0.1` — the flush never reaches, and never could corrupt,
`~/Library/Application Support/WatchLogs/watchlogs.sqlite`. `test-e2e/pages/`
holds the fixture pages it plays; `test-e2e/fixtures/generate-videos.mjs`
regenerates the checked-in video fixtures if you ever need to.

It's kept out of `npm test` and `test/`: it downloads a real Chromium on first
run and takes tens of seconds to run, against the pure suite's sub-second
budget. `test-e2e/content.spec.js` is what to read for what it actually pins —
among other things, a player that never advances but has readyState 0 must
never be reported as playing (the phantom-time bug, fixed in 559c679), and a
frame with no host must still send a non-empty `service` (the empty-`service`
bug, fixed the same commit).

The `chrome.*` calls in `background.js` besides the Flush (pairing, crash
recovery, the tab sweep) still fall to manual QA — loading the unpacked
extension against a running App, as above.

## Known limits of this slice

- **Every media element counts.** With no per-Service Adapter yet, a decorative
  autoplaying `<video>` in a page banner opens a View like any other player.
  Adapters (a later slice) are what tell a real video from page furniture.
- **Metadata is `mediaSession` and best-effort only.** The Service is the bare
  hostname and the video id is `sha1:` of the normalised URL.
- **A frame reports its own teardown as `nav`.** It can't tell a navigation from
  a closing tab on the way out. When the tab really is gone the frame usually
  dies before its write lands, and the worker's sweep reconciles the buffer
  against the live tabs and closes the View `tab-closed` at its last `sample`
  instead — so the reason is right within 30 s either way.
- **Firefox is slice 8.** This is `chrome.*` and an MV3 service worker.
