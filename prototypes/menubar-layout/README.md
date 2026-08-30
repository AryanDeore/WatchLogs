# Prototype: menubar layout

Answers wayfinder ticket [#7](https://github.com/AryanDeore/WatchLogs/issues/7) on map
[#1](https://github.com/AryanDeore/WatchLogs/issues/1).

## Run it

Open `index.html` by double-click. No build, no server. Switch layouts with the
floating bar, the `←` / `→` keys, or `?variant=J|K`. Deep links also take
`&pane=history|services|trends` and `&range=today|week|month`.

## Where the design is now — round 4 (variants J / K)

Rounds 1–3 (A/B/C, D/E/F, G/H/I) are in this branch's git history. Locked in:

- Fixed popover, 380 pt wide. Three data panes, tabbed: **History / By Service /
  Trends**. **Settings** is a top-right gear + slide-over — not a pane, not a tab.
- **Range control on top.** Presets Today / This Week / This Month / Custom.
- **Calendar defaults to a collapsed week row**; a toggle expands it in place to
  the full month. This Month / Custom auto-expand it; Today / This Week collapse.
  No dropdown layer. Calendar days carry no magnitude marks.
- **Trends** = one stacked bar per day over the range, by Service. Orientation
  follows span: **≤ 14 days → horizontal bars**, **> 14 → vertical columns**.
- **By Service** bars are part-to-whole (track = 100% of range time, fill =
  Service share; needs-an-Adapter bucket inside the total).
- **History** per-video bar = how much of that video you've watched (coverage);
  blank for live / unknown length.
- **Summary strip** = top 3 domains, icons + time, no label.
- No "counting" markers. Viz palette departs from brand (YouTube red / Netflix
  amber / Twitch purple) so stacked bars stay legible.

### J vs K

Only the preset placement differs — **J** puts the chips in a row above the
calendar; **K** builds them into the calendar card's header. Nearly identical
when the calendar is collapsed.

## Mock data

One source of truth: `DAILY` (watched minutes per day per Service). History, By
Service and Trends all sum from it. Calendar dates are fictional (Aug 25 2026 =
"Monday").

## Status

Round 4 draft. Open questions in `LAYOUT.md`. **Ticket #7 stays open** — HITL; it
resolves once a direction is locked.
