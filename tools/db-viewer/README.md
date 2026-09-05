# WatchLogs DB viewer

A local, read-only web UI over the WatchLogs SQLite database, for debugging
what's actually landing in it while the Chrome extension flushes. Not part
of the shipped app — a dev tool, like `app/scripts/`.

## Run it

```sh
node tools/db-viewer/server.js
```

Then open the printed URL (default `http://localhost:5183`). It finds the
database at the same default path the app uses
(`~/Library/Application Support/WatchLogs/watchlogs.sqlite`); the app can be
running at the same time — the viewer opens the file read-only, so it can
never write to or corrupt your data.

Override the database path or port if needed:

```sh
node tools/db-viewer/server.js --db=/path/to/other.sqlite --port=6000
# or
WATCHLOGS_DB=/path/to/other.sqlite WATCHLOGS_DB_VIEWER_PORT=6000 node tools/db-viewer/server.js
```

No `npm install` required — the server uses only Node's built-ins
(`node:http`, `node:sqlite`; Node ≥ 22.5 needed for the latter). The
frontend is plain JS with no build step, matching `extension/`'s convention.

## Using it

- **Left pane** — every table in the database with a live row count (the red
  bubble), refreshed every 2s. Click a table to view it.
- **Columns** — drag a header to reorder it; click the 📍 to pin (lock) it to
  the left, so it stays visible while you scroll right through wide tables
  like `raw_events`. Column order and locks are remembered per table
  (localStorage) across restarts.
- **Sort** — click a header to sort by it (click again to reverse, a third
  click returns to the default: newest row first).
- **Filter** — each column has its own filter box (substring match); there's
  also a "Search all columns" box in the toolbar for a quick global filter.
- **Live** — on by default: the current table's rows and every table's count
  re-poll every 2s, so a Flush landing from the extension shows up within a
  couple of seconds. Newly-appeared rows flash briefly. Turn it off to freeze
  the view while you inspect something. The refresh (⟳) button re-polls once
  immediately.

## Why polling, not push

SQLite has no built-in change-notification API. Polling every 2s is simple,
correct, and fast enough for a debugging tool — this isn't a production
dashboard with many concurrent viewers.
