# Menubar layout — decisions so far and open questions

Companion to `index.html`. Material for the HITL reaction on ticket
[#7](https://github.com/AryanDeore/WatchLogs/issues/7). Not itself a decision.

## Locked in (rounds 1–3)

- Fixed-size popover, ~380 pt wide. Not resizable.
- Four **separate** panes, tabbed: **History / By Service / Trends / Settings**.
  Categorical stays a reserved future pane.
- **Range control on top** is the entry point. Presets Today / This Week /
  This Month / Custom. Custom opens a month grid; presets are instant.
- The calendar does **not** carry a per-day heat/dot overview — that job moved to
  the Trends pane. On top there's at most a slim week strip.
- **Trends pane** = one stacked bar per day over the selected range, segmented by
  Service. Granularity follows the range (Week → 7 bars, Month → ~30). A
  single-day range shows that day's mix instead of a 1-bar chart.
- **By Service** bars are part-to-whole: track = 100% of watched time in the
  range, fill = that Service's share. The needs-an-Adapter bucket ("Other sites")
  is inside the denominator. YouTube expands to its `contentFormat` split with
  `embedded` as a sub-line.
- **History** per-video bar = fraction of the video's own timeline watched at
  least once (coverage). Blank for live and when duration is unknown.
- Provisional "Today": lighter total + `counting` pill + a note it re-files at
  `my day ends around`. Past-midnight day is one group under its start date.

## Open questions

1. **Week strip (G/I) vs range dropdown (H).** G/I keep a always-visible
   Mon–Sun strip on top — literally "calendar as entry point" — at the cost of
   ~60 pt of height and a fourth row of range chrome (title total, chips, strip,
   resolved-range line). H collapses all of that into one dropdown button and
   gives the panes the room back. Which?

2. **Trends orientation.** Vertical stacked columns (G/I) read as a rhythm/chart —
   good for a week. Horizontal stacked bars (H) scan as a list and handle a
   sparse month better (most days are empty; see `?variant=H&pane=trends&range=month`).
   Pick one, or switch by range?

3. **Default pane.** History (G/H) or Trends (I)? Now that Trends is the
   at-a-glance overview, it's a candidate for the landing screen.

4. **Settings placement.** A fourth tab (G/I) keeps everything in one row but the
   row gets tight; a gear + slide-over (H) keeps the tab row to the three
   data panes.

5. **Service colours.** YouTube (#ff0033) and Netflix (#e50914) are both red —
   in a stacked Trends bar or a dot they're nearly indistinguishable. The viz
   needs a palette that departs from brand colours (muted brand + distinct hues,
   or a fixed categorical set). This blocks Trends looking right.

6. **Does History still need the coverage bar?** It's the quietest element on the
   row. Keep it (answers "did I finish or bail"), or drop it and let the watched-
   time number stand alone?

7. **The week strip under a Month/Custom range.** Right now it still shows the
   current week as an orientation object while the chips carry the real range.
   Is that a useful "you are here", or just confusing?

## A starting recommendation (react against it)

**H's top with G's Trends.** One compact range dropdown on top — the week strip
looks nice but four rows of range chrome is a lot for a menubar popover, and the
Trends pane already shows the week shape better than a strip can. Land on
**History**. Keep Settings behind a gear. Vertical columns for Trends. Fix the
Service palette before judging Trends.
