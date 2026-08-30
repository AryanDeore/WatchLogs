# Activity-flexed day boundary

## Status

accepted

## Context

WatchLogs reports Watched time per day, week, and month. A daily total is the
headline number, so where one "day" ends and the next begins directly shapes what
the user sees. The obvious choice is local midnight. The next-obvious is a fixed,
user-configurable reset hour (e.g. 04:00), which handles the common "I watched
until 1am" case.

Neither fits a user whose late nights are irregular: some nights they stop at
midnight, some at 4am, occasionally later. Any fixed hour either splits a single
late session across two days or, set late enough to avoid that, pushes genuine
early-morning viewing into the wrong day.

## Decision

The day boundary flexes to the user's activity:

- A day *aims* to end at a **target hour** (user-configurable, default `04:00`
  local).
- If there is no watched-time activity at the target hour, the boundary is the
  target hour.
- If watched-time activity is still in progress at the target hour, the boundary
  **slides** to the end of the next span of **90 minutes with no watched-time
  activity**.
- A fixed **hard cap at `10:00` local** forces the day closed regardless.
- "Activity" means watched-time activity only — video playing AND tab in
  foreground. Background audio and paused tabs do not hold a day open.

Consequences of the model:

- A "day" can exceed 24 hours (a late night that runs long) or be shorter.
- Only the **current open day** is provisional: its total counts live, and may be
  re-filed to the correct day once the boundary is confirmed (90 min idle past
  the target hour, the 10:00 cap firing, or the App relaunching into a gap).
- Once confirmed, a day is **frozen** — its boundaries and totals never change —
  and folded into the pre-aggregated Week/Month tables. Nothing ever re-files
  into a day older than the currently open one.
- Timezone travel and DST never move a frozen day; only the open day is evaluated
  in the App's current timezone.

Segments are stored whole and never cut at a boundary; the date-range layer clips
each Segment's `[start, end)` to the requested window at read time.

## Considered options

- **Local midnight.** Rejected: splits essentially every late session.
- **Fixed configurable reset hour (e.g. 04:00).** Rejected as the sole
  mechanism: still splits or misfiles for an irregular schedule. Retained as the
  *target hour* the flexed boundary starts from.
- **Purely inactivity-driven, no clock.** Rejected: a long daytime gap can look
  like a day boundary, and "what did I watch today" has no answer until the user
  next goes idle.

## Consequences

- Every query that buckets by day, and the Week/Month pre-aggregation job, must
  treat the most recent day as mutable until its boundary is confirmed.
- The UI must not present the current day's total as final.
- Boundary detection needs the merged watched-time timeline across all Views, not
  a per-View view.
