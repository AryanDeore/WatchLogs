# WatchLogs code map

Use this as a fast "where should I look first" guide.

## If the bug is in the Chrome extension capture

### Main capture flow
- `extension/content.js`
- What it does:
  - listens to media events (`play`, `pause`, `seeked`, etc.)
  - opens/changes/closes Views
  - sends events to buffer/worker

### Background worker (flush, ack, pairing)
- `extension/background.js`
- What it does:
  - receives messages from content script
  - posts flushes to the app
  - prunes buffered events after ack
  - now also builds debug bundles

### Metadata merge rules (who wins title/author/duration)
- `extension/src/metadata.js`

### YouTube-specific reading logic
- `extension/src/adapters/youtube.js`

### Generic fallback reading logic
- `extension/src/adapters/generic.js`

### Adapter routing (which adapter binds)
- `extension/src/adapters/router.js`

### Buffer format and rehydrate/prune behavior
- `extension/src/buffer.js`

### Extension tests
- unit tests: `extension/test/*.test.js`
- e2e tests: `extension/test-e2e/*.spec.js`

---

## If the bug is in app rendering (UI)

### History list rows and blue bars
- `app/Sources/WatchLogs/HistoryPane.swift`

### Bar drawing widget
- `app/Sources/WatchLogs/DurationBar.swift`

### Logos and service visuals
- `app/Sources/WatchLogs/ServiceLogo.swift`
- `app/Sources/WatchLogs/FormatLogo.swift`

### Popover layout + tabs
- `app/Sources/WatchLogs/PopoverView.swift`

---

## If the bug is in app read model / computed data

### Read model the UI consumes
- `app/Sources/WatchLogsKit/MenubarPopoverReadModel.swift`

### Data queries + history coverage math + grouping
- `app/Sources/WatchLogsKit/EventStore.swift`

### Segment computation from raw events
- `app/Sources/WatchLogsKit/SegmentComputer.swift`

### Wire schema models
- `app/Sources/WatchLogsKit/FlushEnvelope.swift`
- `app/Sources/WatchLogsKit/ViewRecord.swift`
- `app/Sources/WatchLogsKit/RawEvent.swift`

---

## If the question is "what should behavior be?"

Start here:
- `CONTEXT.md`
- `docs/adr/` (especially 0001, 0002, 0003)

Useful ADR shortcuts:
- Day boundary behavior: `docs/adr/0001-activity-flexed-day-boundary.md`
- At-least-once ingest + ack: `docs/adr/0002-at-least-once-loopback-ingest.md`
- Event->segment logic: `docs/adr/0003-segment-computation-from-event-log.md`

---

## Fast search commands

Use these first to avoid noisy results.

```bash
# Extension capture + metadata
rg -n "change_video|metadata_change|durationSec|ytInitialPlayerResponse" extension/src extension/content.js extension/background.js

# App history bars + coverage
rg -n "coverage|HistoryPane|DurationBar|watchedMs|durationSec" app/Sources/WatchLogs app/Sources/WatchLogsKit

# Skip giant generated/vendor files
rg -n "your pattern" app extension --glob '!**/node_modules/**' --glob '!extension/test-e2e/pages/**/*.html'
```
