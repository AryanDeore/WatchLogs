# Tools

Debug tools. None of this ships with the app; all of it reads the same database
the app writes, and none of it writes to that database.

| | what it answers |
|---|---|
| [`db-viewer`](db-viewer/) | *what is in the database right now?* — every table, live, filterable, with the Lint and Replay tabs |
| [`lint`](lint/) | *is any of this impossible?* — invariant checks over the stored data |
| [`replay-boundary-verdict.js`](replay-boundary-verdict.js) | *would this boundary have frozen or deferred?* — a red/green replay at the first post-target flush |
| `wl-replay` (in [`app/Sources/WLReplay`](../app/Sources/WLReplay)) | *where did this number come from?* — one View, all the way down the pipeline, in the terminal or in db-viewer |

## Why these exist

Four bugs shipped in one week that 161 unit tests and 14 browser end-to-end
tests all passed straight through. Every one of them lived in a **seam** between
two components that were each individually correct and individually tested — the
Extension knowing a tab was hidden while the App assumed it was not; a duration
read from one video landing on another video's row.

A unit test invents its own input, so it can only encode the assumption you
already had. It cannot see a seam. These tools can, because they only ever look
at real captured data:

- `lint` never asks whether a component did what it meant to, only whether the
  result is something that could have happened.
- `wl-replay` puts every stage of one View's journey next to the stage before
  it, so the step where they stop agreeing is visible.

## `wl-replay`

```sh
cd app
swift run wl-replay --recent               # the last few Views
swift run wl-replay --find="lofi"          # by title, author, id or video id
swift run wl-replay <view-id>              # the full report
```

Or use the **Replay** tab in `db-viewer`, which is the same report in the
browser — and where clicking any `view_id` cell in any table opens it. The tab
shells out to this binary rather than porting it, so the web UI shows the app's
own Segment computation; build it once with:

```sh
cd app && swift build --product wl-replay
```

Search matches on words, in any order, with punctuation-only words dropped — so
a title stored with an em dash (`MoErgo Go60 — long term review`, and YouTube
titles are full of them) still turns up when you type an ordinary hyphen, and
half a remembered title is enough.

It prints the View header (and which reader supplied its metadata), the Event
log with Δwall against Δmedia on every step, the stored Segments beside what
*this build* would derive from the same Events, and the History row the popover
renders — including which Views were folded into that row.

Real output, from the row that read "17m13s" for a two-minute watch:

```
  seq  time                 Δwall    Δmedia  type            pos
    2  Sep 5, 2:13:50 PM     0.0s     0.0s  play                 0.0
    3  Sep 5, 2:28:36 PM   14m45s     0.0s  visible              0.0   ⚠ 14m45s of wall clock, 0.0s of video

SEGMENTS  6 stored · 6 recomputed by this build
  watched   Sep 5, 2:13:50 PM → Sep 5, 2:29:08 PM   15m18s  pos 0.0 → 31.9  media 31.9s

HISTORY  what the popover renders for this View
  17m13s · Still watching · live
```

and from a progress bar that read 33% for a video watched end to end:

```
  folded from 2 Views:
  → 679e803a  762.1s     DHH's new setup for programming with AI - te
    6a2d49a0  2177.9s    Omarchy Can Do WHAT?! 50 Features You're Mis  ← a different video
  the bar is measured against 2177.9s — the longest duration in the fold
```

It calls the **shipped** `SegmentComputer` and the shipped read model rather than
re-deriving anything. A tool that re-implemented either would have its own bugs
and could only ever tell you about itself. That is also what makes the
stored-vs-recomputed comparison meaningful: when they disagree, the stored
Segments were written by an older build, and the tool says so instead of leaving
you to wonder whether you are looking at a bug or at history.

By default it works on a snapshot — the database and its write-ahead log copied
to a temporary file — so it is a stable picture of one instant and can never
touch data a running app owns. `--live` opts out.

## `replay-boundary-verdict.js`

A fast boundary yes/no check when "tests passed" is not enough confidence.
It replays one boundary decision from stored data at the **first flush at or
after target hour** and prints a single verdict:

- `FIX WOULD WAIT/SLIDE ✅`
- `WOULD ALLOW FREEZE AT/NEAR TARGET ⚠️`
- `INCONCLUSIVE`

```sh
node tools/replay-boundary-verdict.js
node tools/replay-boundary-verdict.js --date=2026-09-06 --targetHour=4 --windowMinutes=90
```

Defaults: `date = yesterday (local)`, `targetHour = day_settings.target_hour`
(or `4`), `windowMinutes = 90`.
