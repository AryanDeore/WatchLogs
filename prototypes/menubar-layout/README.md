# Prototype: menubar layout

Answers wayfinder ticket [#7](https://github.com/AryanDeore/WatchLogs/issues/7) on map
[#1](https://github.com/AryanDeore/WatchLogs/issues/1).

## Run it

Open `index.html` by double-click. No build, no server. Deep links:
`?pane=history|services|trends` and `&range=today|week|month`.

## Where the design is now — round 5 (converged)

Rounds 1–4 (A/B/C, D/E/F, G/H/I, J/K) are in this branch's git history. The J/K
fork is dropped (they read the same). Locked in:

- Fixed popover, 380 pt wide. Three data panes, tabbed: **History / By Service /
  Trends**. **Settings** is a top-right gear + slide-over — not a pane, not a tab.
- **Range control on top.** Presets Today / This Week / This Month / Custom.
- **Calendar is a collapsed week row** for every preset — the resolved-range
  label (`Aug 25 – Aug 29`) carries the orientation. Only **Custom** expands the
  full month grid; a manual toggle expands/collapses on demand. Calendar days
  carry no magnitude marks.
- **Trends** = one stacked bar per day over the range, by Service. Orientation
  follows span: **≤ 14 days → horizontal bars**, **> 14 → vertical columns**.
- **By Service** bars are part-to-whole (track = 100% of range time, fill =
  Service share; needs-an-Adapter bucket inside the total).
- **History** per-video bar = how much of that video you've watched (coverage);
  blank for live / unknown length.
- **Summary strip** = top 3 domains, icons + time, no label.
- No "counting" markers. Viz palette departs from brand (YouTube red / Netflix
  amber / Twitch purple) so stacked bars stay legible.

## Mock data

One source of truth: `DAILY` (watched minutes per day per Service). History, By
Service and Trends all sum from it. Calendar dates are fictional (Aug 25 2026 =
"Monday").

## Status

Round 5 — converged. Four small things left to confirm in `LAYOUT.md` (default
pane, coverage bar, Netflix colour, the expand toggle). **Ticket #7 stays
open** — HITL; it resolves once those are settled.
