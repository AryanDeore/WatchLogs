# Menubar layout — decisions so far and open questions

Companion to `index.html`. Material for the HITL reaction on ticket
[#7](https://github.com/AryanDeore/WatchLogs/issues/7). Not itself a decision.

## Locked in (rounds 1–4)

- Fixed popover, 380 pt wide, not resizable.
- Three data panes, tabbed: **History / By Service / Trends**. **Settings** is a
  top-right gear + slide-over — not a pane, not a tab. Categorical stays a
  reserved future pane.
- **Range control on top.** Presets Today / This Week / This Month / Custom.
- **Calendar defaults to a collapsed week row.** A toggle expands it in place to
  the full month. Picking **This Month** or **Custom** auto-expands it; **Today**
  / **This Week** collapse it. No dropdown/overlay layer.
- Calendar days carry **no** magnitude marks (no heat, no dots, no underline).
  Just the number, today circled, the selected span as a band.
- **Trends** = one stacked bar per day over the range, by Service. Orientation
  follows span: **≤ 14 days → horizontal bars**, **> 14 → vertical columns**.
  A single-day range shows that day's mix.
- **By Service** bars part-to-whole: track = 100% of range watch time, fill =
  Service share; needs-an-Adapter bucket is inside the total. YouTube expands to
  its `contentFormat` split, `embedded` as a sub-line.
- **History** per-video bar = fraction of the video watched (coverage); blank for
  live / unknown length.
- **Summary strip** under the calendar: top 3 domains, icons + time, no label.
- No "counting" markers. Provisional "Today" is conveyed only by the day name and
  its factual "started … · still open" line.
- **Viz palette** departs from brand so stacked bars stay legible: YouTube red,
  Netflix amber, Twitch purple, Other grey.

## Round-4 variants

- **J** — preset chips in a row above the calendar.
- **K** — presets built into the calendar card's own header.

They are nearly identical when the calendar is collapsed; K only reads as
different once expanded (chips sit visually inside the month card).

## Open questions

1. **J vs K.** Is "presets are part of the calendar" (K) worth it, or is a plain
   chip row above (J) clearer? The visual difference is small.
2. **Expanded month + vertical Trends collide.** Picking This Month expands the
   calendar *and* makes Trends want vertical columns — together they overflow the
   560 pt height (`?variant=J&range=month&pane=trends`). Options: Trends forces
   the calendar collapsed; or the calendar auto-collapses when you leave the
   range-picking moment; or the expand state doesn't persist across pane changes.
3. **Default pane** — still History. Trends as the landing screen (old variant I)
   is still on the table.
4. **Coverage bar in History** — keep (answers "did I finish or bail") or drop?
5. **Month grid density.** The expanded grid's rows are tall; tightening them
   would give the pane below more room.
6. **Netflix = amber** is a deliberate lie for legibility. Acceptable, or find
   another way to separate the two reds (pattern fills, outlines)?

## Starting recommendation

Go with **J** (plainer). Make **Trends force the calendar collapsed** so the
chart always has room; keep the expand behaviour for History / By Service. Land
on History. Keep the coverage bar. Tighten the month grid rows.
