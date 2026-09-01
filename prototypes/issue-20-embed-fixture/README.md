# issue-20-embed-fixture

Not a design prototype — a manual QA fixture for exercising acceptance
criterion #6 of [#20](https://github.com/AryanDeore/WatchLogs/issues/20):
"A player embedded in a third-party page is captured with `embedded = true`."

`index.html` (served on host `localhost`) iframes `video.html` (served on host
`127.0.0.1`, same server, same port) — a different hostname counts as a
different site for `isEmbedded()`, which only compares hostnames. `video.html`
plays a public-domain MDN sample `.mp4` directly, so there's no third-party
"embedding disabled" flag (unlike a YouTube iframe) to make the test flaky.

## Use

```
python3 -m http.server 8000 -d prototypes/issue-20-embed-fixture
```

Open `http://localhost:8000/` (not `127.0.0.1` — that's the iframe's host,
not the top page's), load the WatchLogs extension unpacked, let the muted
video autoplay inside the iframe, then check:

```
sqlite3 ~/Library/Application\ Support/WatchLogs/watchlogs.sqlite \
  "select view_id, service, embedded, url from views order by rowid desc limit 5;"
```

Look for a row with `service = youtube.com` and `embedded = 1`.
