# Day Boundary panel (db-viewer)

The Day Boundary tab is a **generic boundary diagnostics tool**.

It is for questions like:

- "Did activity actually cross the target hour?"
- "At the first post-target flush, what activity did the app know about?"
- "Would current logic defer (slide) or allow freeze?"

## Open it

1. Run:
   ```bash
   node tools/db-viewer/server.js
   ```
2. Open `http://localhost:5183`
3. Click **📅 Day Boundary**

## Inputs

- **Date**: boundary date (`YYYY-MM-DD`)
- **Target hour**: hour boundary (0–23)
- **Window min**: slide window in minutes (normally 90)

## Output sections

- **Boundary analysis**: computed target instant + summary
- **Timeline**: key flushes and crossing activity around target
- **Crossing segment**: one watched segment spanning target (if present)
- **Newest activity at decision**: what data existed at first post-target flush
- **Fix behavior**: whether current near-boundary logic would defer freeze
- **Actual vs expected**: persisted `rolled_day` end compared with `lastActivity + window`

## API

The UI reads:

`GET /api/day-boundary?date=YYYY-MM-DD&targetHour=H&windowMinutes=N`

Server route: `tools/db-viewer/server.js`  
Analyzer: `tools/db-viewer/day-boundary-diagnostics.js`

## Related CLI check

For a one-line red/green verdict at the same decision seam, use:

```bash
node tools/replay-boundary-verdict.js --date=2026-09-06 --targetHour=4 --windowMinutes=90
```

This complements the Day Boundary panel:

- Panel = detailed visual timeline
- Verdict tool = quick yes/no verdict
