# Segment computation: turning a View's Event log into Watched time

## Status

accepted

## Context

The App receives a raw, `seq`-ordered Event stream per View (`play`, `pause`,
`seeked`, `visible`/`hidden`, `pipEnter`/`pipLeave`, `ratechange`, `sample`,
`ended`, `viewEnded`, …) and must derive **Segments** — continuous spans of real
time when the View's Watched conditions held — and from them **Watched time**.
The Event stream is lossy (heartbeats and events can be dropped or delayed),
duplicated (at-least-once ingest, ADR 0002), and stamped with a clock the App
does not control. Several rules for collapsing that stream into Segments are
non-obvious and expensive to change once Segments are stored and downstream
panes/aggregation depend on them.

## Decision

**One state machine, two conditions.** A Segment is a maximal wall-clock span
where the video is `playing` **and** in the foreground, where foreground means
`visible OR picture-in-picture`. Every Segment has a `kind`: `watched` when
foreground, `background` when playing but not foreground. Watched time for a View
is the sum of its `watched` Segment lengths; `background` accrues a separate
total and never counts as Watched time. `ratechange`, `metadataChange`, and the
PiP toggles never open or close a Segment; `mediaFound` starts the View, not a
Segment.

**Watched time is wall-clock, never media time.** 60 real seconds at 2× playback
is 60 seconds of Watched time. Re-watching a span produces a second Segment and
counts again (cumulative, per `CONTEXT.md`).

**A seek splits a Segment.** `seeked{from,to}` during an open Segment closes it at
media position `from` and opens a fresh one at `to`, at the same instant with no
wall-clock gap. One uninterrupted playthrough with N seeks yields N+1 Segments,
each covering a single continuous media range. Skipped ranges are covered by no
Segment; re-covered ranges (backward seek) are covered by two. The App does not
separately record "skipped" or "re-watched" ranges.

**Only positively-confirmed time counts (conservative loss-bounding).** An
explicit event with a real timestamp is trusted exactly. When a boundary must be
*inferred* — a `sample` reveals a state with no preceding event, or heartbeats
are missing — the Segment ends at the last timestamp that positively confirmed
all conditions (the last good `sample` or event); the uncertain gap is excluded.
A crash-recovered tail (`viewEnded{reason: crash-recovered}`, stamped at the last
`sample` per the message schema) is closed there, not extrapolated and not
discarded.

**Duplicates removed on `(viewId, seq)`; computation is a pure function.** Stable
Event identity is `(viewId, seq)`; timestamp is not part of identity. Segment
computation reads a View's `raw_events` distinct on `(viewId, seq)`, ordered by
`seq`, and is a pure function of that ordered log — re-run for a View whenever new
Events land for it, including a late retry or a crash-recovery Flush hours later.
An open View's trailing Segment is `provisional` and replaced on recompute.

**Clocks:** store the Extension's raw timestamps; never rewrite them into
Segments. Guard per-View monotonicity — an Event whose `t` precedes its
predecessor's is clamped to the predecessor's `t` (`seq` is the ordering
authority). Per-Flush skew (`receivedAt − sentAt`) is recorded as a diagnostic
and fed to the merged cross-View timeline, not baked into Segment times.

**Noise floor:** after seek-splitting, discard any Segment shorter than 1000 ms
(both kinds). Store wall times to the millisecond; sum in milliseconds and round
to whole seconds once, at the end of a sum — never per Segment.

**Day-agnostic.** Segments are emitted whole regardless of when their Events
arrive. Calendar bucketing and the frozen-day rule (ADR 0001, activity-flexed
day boundary) live entirely in the read-time date-range layer and the Week/Month
pre-aggregation job (issue #11), which decide what a frozen day does with a
late-arriving Segment.

## Considered options

- **Optimistic loss-bounding** — extend a Segment to the heartbeat that revealed
  a stopped state. Rejected: silently inflates every number in the app; a few
  seconds of under-count is honest and barely visible.
- **One Segment with a piecewise media-range list across seeks.** Rejected: every
  Segment stops being a single clean span, complicating every consumer, to
  preserve information (exact skip/rewatch geometry) no v1 pane uses.
- **Media-time Watched total** (2× ⇒ double). Rejected: `CONTEXT.md` defines
  Watched time as real time spent; media consumed is still derivable from a
  Segment's `posEnd − posStart`.
- **Focus-aware foreground** so only the focused one of two visible windows
  counts. Rejected for v1: the message schema has no focus/blur signal and
  `visibilitychange` does not fire between two visible windows; both visible
  windows accrue Watched time. Left as a future refinement.
- **Exactly-once / front-door dedupe.** Rejected upstream in ADR 0002; Segment
  computation dedupes on `(viewId, seq)` instead.

## Consequences

- A still-open View's Watched time trails real time by up to one `sample`
  interval (~5 s); the "Today" pane must treat the current total as live, not
  final.
- Segment counts look high: one playthrough with heavy scrubbing is many
  Segments. Downstream code must never assume one Segment per play session.
- `provisional` Segments exist in the `segments` table; the pre-aggregation job
  must not freeze a day while it still contains a provisional Segment.
- Live streams need no special logic — `posStart`/`posEnd` are null when the
  player reports no position; Watched time is still wall-clock.
- A View's own history (whole, unclipped Segments) can show slightly more time
  than a frozen day's headline total after a late crash-recovery Flush; #11 owns
  that reconciliation.
