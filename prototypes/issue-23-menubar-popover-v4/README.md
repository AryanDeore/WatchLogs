# Prototype: menubar popover, v4 — sidebar rail switcher (F)

Answers issue [#23](https://github.com/AryanDeore/WatchLogs/issues/23) (slice 6 of
the [tracer-bullet build](https://github.com/AryanDeore/WatchLogs/issues/18)).

`prototypes/issue-23-menubar-popover-v2/` settled the *chrome* question — native
macOS idioms over a ported web page — but left the pane switcher open.
`prototypes/issue-23-menubar-popover-v3/` showed eight candidates for that
switcher against a stub. This prototype takes **v3's variant F (sidebar rail)**
and drops it into v2's real, fully-built chrome, so the rail can be judged
against actual panes rather than a placeholder.

Sibling: `prototypes/issue-23-menubar-popover-v5/` does the same for variant A
(segmented control).

## Question

The rail's whole pitch is that it moves the switcher off the **height** budget,
which is the scarce axis in a fixed-height popover. Its whole cost is **width**,
which in v3 meant carving ~54pt out of the panes' 380pt.

This prototype refuses that trade and asks a different question: **what if the
window just gets wider instead?** The rail is added beside the panes rather than
carved out of them. First cut: panes kept exactly v2's 380pt and the window grew
to 435pt — which read as too wide, so the window is now **370pt** (435 × 0.85),
with the 65pt difference taken out of the pane column (315pt) rather than the
44pt rail items, which were already close to the minimum that still fits an icon
plus an 8pt label. So:

- Is a 370pt-wide menu-bar popover still comfortable, or does it start to feel
  like a window rather than a menu?
- Does the vertical rail earn a permanent column for three items, now that it's
  costing pane width (315pt vs. v2/v5's 380pt) rather than just window width?

## Run it

```
cd prototypes/issue-23-menubar-popover-v4
swift run
```

Look for **"4"** in the menu bar (`4.circle.fill`). `Ctrl+C` or
`killall MenubarPopoverPrototypeV4` to stop. Run it alongside v2 ("2") and v5
("5") to compare directly.

## What's different from v2

Exactly two files, plus one enum case:

| File | Change |
|---|---|
| `TabBar.swift` → `PaneRail.swift` | Horizontal icon+label bar replaced by a vertical rail: 44pt items, icon over an 8pt label, accent-filled selection, faint `Color.primary.opacity(0.04)` backing to read as a sidebar. |
| `PopoverView.swift` | Window fixed at 370pt (see above); the rail and the scrolling pane sit in an `HStack` below the summary strip, with the pane pinned to `370 - PaneRail.width - 1` (315pt). Height is now dynamic — see below. |
| `MockData.swift` | `Pane.shortLabel` added — "By Service" doesn't fit 44pt, so the rail says "Services". |
| `HeightReader.swift` | New — same measurement helper as v2, carried over so this prototype gets the same dynamic-height fix (below) rather than drifting from it. |

Everything else — mock data, state model, History / By Service / Trends, the
calendar, Settings, the thin scrollbar — is byte-identical to v2.

### Dynamic height

Also carried over from v2 (both were fixed at the same time, from the same
report — a 14-day Custom-range Trends chart getting squeezed out by the
expanded month calendar, forcing a scroll to see the last few bars): the window
height is no longer a fixed 560pt. `ThinScrollView` already measured its own
content's height for the scrollbar-knob math; that's now piped up via a
callback, combined with a `measureHeight` on the chrome above the rail/pane row,
and used to size the window directly — clamped to a floor and a ceiling (past
which `ThinScrollView` scrolls, as before). Same behavior as v2: a short pane
shrinks the window, a tall one (up to the ceiling) grows it.

### Where the rail starts

The rail begins **below** the summary strip, not at the top of the window. The
title row, range presets, calendar, and summary strip apply to all three panes
equally; a full-height sidebar in the Mail/Finder sense would imply it governed
those too. So the rail is the pane area's own chrome, and the window reads as a
header band over a sidebar+content pair.

That is a judgement call and the obvious alternative — a true full-height rail
with the header pushed to the right of it — is worth trying if this direction
survives.

## Status

Not production code, not wired to `WatchLogsKit`. Compare against v2 (icon +
label) and v5 (segmented) to pick the switcher for issue #23's real
implementation in `app/Sources/WatchLogs`.
