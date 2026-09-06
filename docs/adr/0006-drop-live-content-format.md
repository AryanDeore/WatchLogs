# Drop `live` as a contentFormat

## Status

accepted

## Context

`contentFormat = "live"` was being used for two unrelated jobs:

1. deciding whether to skip long-gap clawback in segment computation, and
2. deciding whether History should draw a coverage bar.

That label is not reliable enough to carry either job. On YouTube, the marker we used can be present on ended-stream replays and missing on genuinely live streams (especially after in-page navigation). That made `live` effectively a coin flip, and the wrong value could inflate Watched time by minutes.

## Decision

- `contentFormat` now has two values: `standard` and `short`.
- Segment computation no longer takes `isLive`; long-gap clawback applies to every View the same way.
- History coverage no longer checks for `contentFormat == "live"`.
- Coverage is shown only when the View has a trustworthy fixed duration.
  - For now: duration must be present, positive, and no more than 12 hours.
  - Longer values are treated as sliding DVR windows (not a real fixed length), so coverage is hidden.
- YouTube adapter still reads video ids from `/live/<id>`, but reports `contentFormat = "standard"`.
- Legacy stored `"live"` values are read as `"standard"`.

## Considered options

- **Keep `live` and improve detection.** Rejected: still tied to brittle page markers and navigation mode.
- **Migrate every stored row from `live` to `standard` in SQL.** Deferred: not required for correctness because read-time normalization removes behavior from stored `live` immediately.

## Consequences

- A background-tab gap on a live stream is treated like any other gap: only believable playback is counted.
- History’s coverage bar behavior is tied to duration quality, not format labels.
- Very long true VODs (>12h) will currently hide coverage as a conservative tradeoff.
