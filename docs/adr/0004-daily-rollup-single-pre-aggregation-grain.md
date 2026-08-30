# Daily rollup as the single pre-aggregation grain

## Status

accepted

## Context

The Week and Month tabs must feel instant, so their totals are read from a
pre-aggregated table rather than recomputed from `segments` on every open. Issue
#8 called for full weeks and months "pre-aggregated into their own tables". But
an activity-flexed **Day** (ADR 0001) is the only bucket that ever *freezes*, and
#8 also fixed the Day as the smallest unit the UI works in — no time-of-day
fields, ranges are whole Days. So a week or a month is always an exact whole
number of frozen Days, and a per-week or per-month table would be a second
aggregation layer over the one that already matters.

## Decision

One rollup grain: the frozen **Day**. Two tables, both a pure cache derived from
`segments`:

- `rolled_day` — one row per processed frozen Day: `logical_date` (the Day's
  label, i.e. the calendar date it began), `day_start_ms`, `day_end_ms` (the
  absolute epoch-ms boundaries the flex landed on, never re-evaluated),
  `schema_version`.
- `rollup_slice` — one row per `logical_date` × `service` × `contentFormat`:
  `watched_ms`, `background_ms`.

There is **no week table and no month table**. Week, Month, and whole-Day Custom
ranges are all `SUM(rollup_slice)` over the `logical_date`s in range, plus a live
`openDayTotals()` compute for the current open Day whenever the range includes
today (today's `segments` clipped to `[provisional_day_start, now)`, sliced the
same way). Range membership follows the Day's **label**, not its wall-clock end:
a Day labelled Aug 25 that ran to 05:10 on Aug 26 counts in the week containing
Aug 25 and in August.

The rollup job runs (a) on day-freeze — compute that Day's rows by summing its
Segments clipped to `[day_start_ms, day_end_ms)`; (b) on App launch — a
reconciliation pass folds in any confirmed-frozen Day with no `rolled_day` row;
(c) on demand — a manual "Rebuild statistics" action, also triggered by a
`schema_version` mismatch. The current open Day is never touched by the job.

Rollups are kept forever otherwise (a few thousand rows a year) and are exempt
from the `raw_events` 90-day prune. An **empty Day** (no watched-time activity)
is a `rolled_day` row with zero `rollup_slice` children.

## Considered options

- **Separate `week_rollup` / `month_rollup` tables** (issue #8's original
  wording). Rejected: two more tables that each need their own frozen-vs-mutable
  bookkeeping, and they still cannot serve the partial current week or month
  without the same live open-Day compute. Summing ~30 daily rows is already
  sub-millisecond in SQLite with an index on `logical_date`.
- **Rollups as a source of truth**, letting `segments` be pruned against them.
  Rejected: `segments` are kept forever and re-derivable, so a rollup rebuild is
  always possible; making rollups authoritative only makes every rollup-job bug
  permanent.
- **Empty Day writes zero `rollup_slice` rows.** Rejected in favour of a bare
  `rolled_day` row — it records "this Day was processed" without inventing rows
  the By-Service pane would just sum to nothing.

## Consequences

- Supersedes issue #8 point 6's "their own tables": there is no week or month
  table.
- Every date range — Today, Week, Month, Custom — reads this one table. #8's
  "custom ranges computed on the fly, a short delay is acceptable" now only
  applies when the rollup cache has been dropped and not yet rebuilt.
- The By-Service pane's per-`contentFormat` lines (e.g. YouTube standard vs
  YouTube Shorts shown separately) come straight from `rollup_slice`'s grain;
  how they are grouped and rendered is issue #7's concern.
- The job must not process a Day while it still contains a `provisional` Segment
  (ADR 0003).
- The reconciliation pass makes the freeze -> rollup step crash-safe without a
  transaction spanning both.
