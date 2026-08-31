# WatchLogs extension — loopback handshake (issue #26)

A minimal Chromium **unpacked** extension. It has no playback capture yet; it
only proves the transport: take a pasted pairing string, post an empty-`views`
Flush on a timer, process the Ack, and drop to a "re-pair" state on `401`.

## Load it

1. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → pick
   this `extension/` directory.
2. Open the WatchLogs menubar app, choose **Copy Pairing String**.
3. Open the extension's **Options** (or the toolbar popup → *Open pairing
   settings*), paste, click **Pair**. On success the heartbeat starts and the
   menubar app moves to **Connected**.

## Layout

| File | Role |
|---|---|
| `manifest.json` | MV3; `storage` + `alarms` permissions, `http://127.0.0.1/*` host permission (the CORS exemption) |
| `background.js` | service worker: heartbeat timer, `POST /v1/flush`, Ack handling; `401` → stop timers, forget the pairing, re-pair state |
| `src/pairing.js` | pure: parse / encode the base64 pairing string |
| `src/flush.js` | pure: build the heartbeat envelope, validate the Ack, decide accept / re-pair / retry |
| `src/state.js` | pure: connection-state reducer + one-line summary |
| `options.html` / `options.js` | paste + pair, pings `/v1/ping` before storing |
| `popup.html` / `popup.js` | shows the current connection line |

The pairing string is stored in `chrome.storage.local` — never in a bundled
file.

## Test

```
npm test        # node --test over the pure modules in src/
```

The service worker and DOM files are exercised by loading the unpacked extension
against a running App (manual QA above).
