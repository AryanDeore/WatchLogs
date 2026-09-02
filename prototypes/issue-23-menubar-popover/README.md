# Prototype: menubar popover in SwiftUI

Answers issue [#23](https://github.com/AryanDeore/WatchLogs/issues/23) (slice 6 of
the [tracer-bullet build](https://github.com/AryanDeore/WatchLogs/issues/18)) on top
of the layout pinned by `prototypes/menubar-layout/` (issue
[#7](https://github.com/AryanDeore/WatchLogs/issues/7)).

## Question

The HTML prototype at `prototypes/menubar-layout/` converged on a layout (round 5).
This prototype asks: **does that layout hold up as a real macOS `MenuBarExtra`
popover** — native controls, SwiftUI layout quirks, actually clicking a menu-bar
icon — or does something need to change before it's worth wiring to the real
`totals(range, groupBy)` read model?

## Run it

```
cd prototypes/issue-23-menubar-popover
swift run
```

Click the eye icon that appears in the menu bar. `⌘Q` or `killall
MenubarPopoverPrototype` to stop it — it's an unsigned, unbundled binary so it won't
show up in the Dock.

## What's mirrored from `prototypes/menubar-layout/`

Same single mock dataset (`MockData.daily`, in minutes per Service per day-of-month
for a fictional August 2026, "today" = Aug 29) and the same round-5 decisions:

- Fixed 380×560 popover. Title row (`Watch·Logs · <range> · <total>`) with a gear
  that opens Settings as a slide-over, not a tab.
- Preset chips (Today / This Week / This Month / Custom) driving one range across
  all three panes.
- Calendar collapsed to a week row for every preset; only Custom expands the full
  month grid; a manual toggle also works.
- Summary strip: top-3 Services, click-through to By Service.
- Tabs: History (day groups, per-View coverage bar, blank for live) / By Service
  (part-to-whole bars, YouTube expandable to its format split, "Other sites" bucket
  for the needs-an-Adapter domains) / Trends (horizontal bars ≤ 14 days, vertical
  columns beyond that).
- Viz palette departs from brand (YouTube red / Netflix amber / Twitch purple /
  Other grey).

`Theme.swift` ports the HTML's CSS custom properties (`--ink`, `--panel`, `--line`,
`--accent`, the `--yt`/`--nflx`/`--twitch`/`--other` viz palette, etc.) as exact hex
`Color`s, and every view was re-pointed at `Theme.*` instead of system/semantic
colors (`Color.secondary`, `NSColor.controlBackgroundColor`, ...) so the popover
doesn't drift under light/dark mode or accent-color changes — the HTML has no dark
mode, so this prototype forces `.preferredColorScheme(.light)` to match. Font sizes,
weights, paddings, corner radii, and column widths were matched to the CSS px
values point-for-point (e.g. the Trends row label/value columns are 52pt, matching
`grid-template-columns: 52px 1fr 52px`).

## What's SwiftUI-specific

- State is one `@Observable` `PopoverStore`, passed down with `@Bindable` — no
  central `render()`/diff step like the HTML version.
- `MenuBarExtra(_:systemImage:) { }.menuBarExtraStyle(.window)` gives a real
  popover-like window anchored to the menu bar for free; no custom positioning code.
- The week-row / month-grid range highlight uses `UnevenRoundedRectangle` to round
  only the start/end cell of a selected span, matching the HTML's `.r-start`/`.r-end`
  behavior instead of rounding every cell.
- No deep links (`?pane=`/`&range=`) — not worth it for a single local run.

## Findings

- The layout translates cleanly: fixed-size popover, segmented tabs, part-to-whole
  and stacked bars, and the collapsed/expanded calendar all have direct native
  SwiftUI equivalents (`GeometryReader`-based bars, `LazyVGrid` for the month grid,
  `.menuBarExtraStyle(.window)` for the popover chrome).
- `Color.primary`/`.secondary`/`.tertiary` are `ShapeStyle`, not `Color` — ternaries
  mixing them with a literal `Color` (e.g. `.white`) need an explicit `Color(...)`
  on every branch. Solved by moving everything to the `Theme.*` hex constants,
  which are plain `Color`.
- Verified with `swift build` (clean) and a `swift run` smoke test (launches,
  stays alive, no crash). Pixel-diffing this against a screenshot of
  `prototypes/menubar-layout/index.html` was attempted but blocked: `screencapture`
  fails with "could not create image from display" — the terminal process running
  this session doesn't have Screen Recording permission (System Settings › Privacy
  & Security › Screen Recording), and granting it isn't something an agent can do.
  Visual comparison against the HTML is a manual step: `swift run` here alongside
  opening `prototypes/menubar-layout/index.html` in a browser.

## Status

Not production code, not wired to `WatchLogsKit`. If the layout holds up under
manual review, issue #23's real implementation lives in `app/Sources/WatchLogs`
against the actual read model.
