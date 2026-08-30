# Menubar layout — decisions and what's left

Companion to `index.html`. Material for the HITL reaction on ticket
[#7](https://github.com/AryanDeore/WatchLogs/issues/7).

## The layout (converged, round 5)

- Fixed popover, 380 pt wide.
- **Title row:** `Watch·Logs · <range> · <total>` with a **Settings gear** far
  right → slide-over. Settings is not a pane and not a tab.
- **Preset chips:** Today / This Week / This Month / Custom.
- **Calendar:** a collapsed week row (current week, today circled, selected span
  as a band) + the **resolved-range label** (`Aug 25 – Aug 29`) + an expand
  toggle. Stays collapsed for every preset — the label carries the orientation.
  **Only Custom** expands the full month grid (needed to pick arbitrary days);
  the manual toggle still expands/collapses on demand.
- **Summary strip:** top 3 domains, icon + time, no label. Click → By Service.
- **Tabs:** History / By Service / Trends.
  - **History** — Views grouped by activity-day (past-midnight day is one group
    under its start date). Per-video bar = fraction of the video watched
    (coverage); blank for live / unknown length.
  - **By Service** — part-to-whole bars: track = 100% of range watch time, fill =
    that Service's share; the needs-an-Adapter bucket ("Other sites") is inside
    the total. YouTube expands to its `contentFormat` split, `embedded` sub-line.
  - **Trends** — one stacked bar per day over the range, by Service. Orientation
    follows span: **≤ 14 days → horizontal bars**, **> 14 → vertical columns**.
- **Viz palette** departs from brand for legibility: YouTube red, Netflix amber,
  Twitch purple, Other grey. (Both brands are red in reality.)
- No "counting" markers. No magnitude marks on calendar days. No footer.

## Still to confirm

1. **Default pane** — currently History. Flip to Trends if the per-day overview
   should be the landing screen. (One line.)
2. **Coverage bar in History** — keep it (answers "did I finish or bail"), or
   drop it as noise?
3. **Netflix = amber** — a deliberate departure from brand red so it separates
   from YouTube in stacked bars / dots. OK, or solve it another way (hatching,
   outlines, keep both red)?
4. **The manual expand toggle** — still worth having now that presets never
   expand the calendar? (It's the only way to eyeball a month without switching
   to Custom.)

## Prior rounds

A/B/C (round 1), D/E/F (round 2), G/H/I (round 3), J/K (round 4) — all in this
branch's git history.
