# Prototype: menubar popover, v5 — segmented-control switcher (A)

Answers issue [#23](https://github.com/AryanDeore/WatchLogs/issues/23) (slice 6 of
the [tracer-bullet build](https://github.com/AryanDeore/WatchLogs/issues/18)).

`prototypes/issue-23-menubar-popover-v2/` settled the *chrome* question — native
macOS idioms over a ported web page — but left the pane switcher open.
`prototypes/issue-23-menubar-popover-v3/` showed eight candidates for that
switcher against a stub. This prototype takes **v3's variant A (segmented
control)** and drops it into v2's real, fully-built chrome.

Sibling: `prototypes/issue-23-menubar-popover-v4/` does the same for variant F
(sidebar rail).

## Question

Variant A is the cheapest possible answer: the stock
`Picker(...).pickerStyle(.segmented)`. No custom drawing, so selection
behaviour, focus ring, Dark Mode, and accessibility all come from the system.

The thing to actually look at when you open it: **the range presets directly
above are also a segmented Picker.** The panel now leads with two identical
controls stacked one on top of the other, meaning two completely different kinds
of thing — "which days" and "which view of those days". Is "instantly familiar
control" worth "the same control twice"?

Secondary: it's text-only, so panes read as words rather than glyphs, and it
spends a full row of height — the axis a fixed-height popover has least of.

## Run it

```
cd prototypes/issue-23-menubar-popover-v5
swift run
```

Look for **"5"** in the menu bar (`5.circle.fill`). `Ctrl+C` or
`killall MenubarPopoverPrototypeV5` to stop. Run it alongside v2 ("2") and v4
("4") to compare directly.

## What's different from v2

One file. `TabBar.swift`'s hand-built icon+label row is replaced by a stock
segmented `Picker` bound to `store.pane`, at the same padding so the rest of the
layout doesn't shift. Same 380pt width. Mock data, state model, panes, calendar,
Settings, and the thin scrollbar are byte-identical to v2.

## Status

Not production code, not wired to `WatchLogsKit`. Compare against v2 (icon +
label) and v4 (sidebar rail) to pick the switcher for issue #23's real
implementation in `app/Sources/WatchLogs`.
