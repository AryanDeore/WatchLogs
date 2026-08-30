# Prototype: menubar layout

Answers wayfinder ticket [#7](https://github.com/AryanDeore/WatchLogs/issues/7) on map
[#1](https://github.com/AryanDeore/WatchLogs/issues/1).

## Run it

Open `index.html` by double-click. No build, no server. Switch layouts with the
floating bar, the `←` / `→` keys, or `?variant=G|H|I`. Deep links also take
`&pane=history|services|trends|settings` and `&range=today|week|month`.

## Where the design is now — round 3 (variants G / H / I)

Rounds 1 (A/B/C) and 2 (D/E/F) are in this branch's git history. Decisions locked
in from those rounds:

- **Separate, tabbed panes.** History (the event-log grain), By Service (range
  totals), Trends (per-day rhythm), Settings — different grains, not one scroll.
- **The calendar is not the hero.** It shrinks to a compact **week strip** pinned
  at the top as the entry point; a month grid drops down only for **Custom**.
- **New Trends pane.** One stacked bar per day across the selected range,
  segmented by Service — the per-day overview the shrunk calendar gave up.
- **Service summary strip** under the range control (from F), now with icons.
- **By Service bars are part-to-whole:** the track is 100% of watched time in the
  range, the fill is that Service's share; the "needs an Adapter" bucket is
  inside the total so the parts sum to the whole.
- **History's per-video bar = coverage** — how much of that video you've watched
  at least once. Blank for live / unknown length.

### The three variants

| | top control | Settings | Trends | lands on |
|---|---|---|---|---|
| **G** | week strip + preset chips | 4th tab | vertical stacked columns | History |
| **H** | one range dropdown (most compact) | gear → slide-over | horizontal stacked bars | History |
| **I** | week strip + preset chips | 4th tab | vertical stacked columns | **Trends** |

G and I differ only in the default pane — I tests whether the per-day chart is
the natural home screen now that the calendar shrank. H trades the always-visible
week strip for vertical space and scans a sparse month as a list.

## Mock data

One source of truth: `DAILY` (watched minutes per day per Service). History, By
Service and Trends all sum from it, so the numbers reconcile across panes. The
calendar dates are fictional — Aug 25 2026 is treated as "Monday".

## What's throwaway vs. what lifts

- **Throwaway:** the whole page — variant shells, the faux menubar, the switcher,
  the mock data.
- **Lifts:** only the decisions, captured in `LAYOUT.md` and folded into the spec.

## Status

Round 3 draft. Open questions for the next reaction are in `LAYOUT.md`. **Ticket
#7 stays open** — HITL; it resolves once a direction is locked.
