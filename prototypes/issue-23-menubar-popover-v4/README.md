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
window just gets wider instead?** The panes keep exactly the 380pt they have in
v2, the rail is added beside them, and the window grows to 435pt. So:

- Is a 435pt-wide menu-bar popover still comfortable, or does it start to feel
  like a window rather than a menu?
- Does the vertical rail earn a permanent 54pt column for three items?

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
| `PopoverView.swift` | Window widened to `380 + PaneRail.width + 1`; the rail and the scrolling pane sit in an `HStack` below the summary strip, with the pane pinned to 380pt. |
| `MockData.swift` | `Pane.shortLabel` added — "By Service" doesn't fit 44pt, so the rail says "Services". |

Everything else — mock data, state model, History / By Service / Trends, the
calendar, Settings, the thin scrollbar — is byte-identical to v2.

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
