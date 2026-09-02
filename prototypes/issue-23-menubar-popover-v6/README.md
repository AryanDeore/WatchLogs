# Prototype: History-row duration bar height — v6

Answers a narrower question spun out of issue
[#23](https://github.com/AryanDeore/WatchLogs/issues/23): the per-video
"how much of this did you watch" bar under each row in the History pane
(v1/v2/v4/v5 all use a stock `ProgressView`) reads too bold — every row looks
equally important whether it's a 3-second Short or a 2-hour movie. This
prototype does nothing but show the same six History rows with that one bar
swapped between six height options.

## Run it

```
cd prototypes/issue-23-menubar-popover-v6
swift run
```

Look for **"6"** in the menu bar (`6.circle.fill`). Use the **‹ ›** arrows in
the bottom bar to page through the variants — the rationale for whichever one
is showing sits right underneath it. `Ctrl+C` or `killall
MenubarPopoverPrototypeV6` to stop.

The chrome around the rows (title row, range presets, summary strip) is real
enough that the bar is judged in context; the six rows themselves are fixed
across every variant (same six MockData.history views, coverage spread from
35% to 100%, plus one live view with no bar at all) so height is the only
thing changing.

## The six options

| | Variant | The trade |
|---|---|---|
| **A** | Stock `ProgressView` | What ships today. No explicit height — macOS's own linear style, which renders thick and fully saturated. |
| **B** | 5pt capsule | Close to stock's rendered height; the reference point before going thinner. |
| **C** | 4pt capsule | Still clearly a progress bar, noticeably quieter. Matches the thickness the aggregate Trends bars already use elsewhere. |
| **D** | 3pt capsule | Reads as a detail rather than a headline — present without competing with the title above it. |
| **E** | 2pt capsule | Close to a divider's weight. Coverage is still legible, but a full and an empty row look similar without a second look. |
| **F** | 1pt hairline | Barely there. Included as the floor of the sweep, not a real candidate. |

## The actual decision

Leaning **C (4pt)**: it's the first height where the bar stops competing with
the title text, and reusing the Trends bars' thickness means one bar-weight
language across the whole popover instead of two. **D (3pt)** is worth a
second look if C still feels heavy in context. **A** (stock) is the thing
being moved away from, and **E/F** trade away legibility a "did I finish
this?" glance actually wants.

## What's shared with v1 / v2 / v3

`MockData.swift` and `ServiceLogo.swift` are copied over unchanged, same as
v3, so the shell renders the same fictional dataset and service marks. The
six rows shown here are inlined in `BarGalleryView.swift` rather than pulled
live from `MockData.history`, so the set judged is fixed regardless of what
future edits do to that array.

## Status

Not production code. Pick a height here, then fold it into HistoryPane's
`ViewRow` in whichever prototype's chrome direction wins for issue #23.
