# Prototype: menubar popover — segmented-control switcher (A)

Answers issue [#23](https://github.com/AryanDeore/WatchLogs/issues/23) (slice 6 of
the [tracer-bullet build](https://github.com/AryanDeore/WatchLogs/issues/18)).

This is the design that was settled on, and the only one still on disk. It got
here in three steps: **v2** settled the *chrome* question — native macOS idioms
over a ported web page — but left the pane switcher open; **v3** showed eight
candidates for that switcher against a stub; this one takes **v3's variant A
(segmented control)** and drops it into v2's real, fully-built chrome. v4 did
the same for variant F (a sidebar rail) and lost.

v1–v4 and v6 were deleted once the choice was made. They are in the history
behind commit `85d5ba2` if the head-to-head is ever worth rerunning.

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
cd prototypes/issue-23-menubar-popover
swift run
```

Look for the **stepped-bars mark** in the menu bar — concept A from
`prototypes/app-logo-concepts/`, carried in as `MenuBarIcon.swift`. It replaced
the old `5.circle.fill` numeral, which only existed so several prototype
versions could sit in the menu bar at once. `Ctrl+C` or
`killall MenubarPopoverPrototype` to stop.

## What's different from v2

`TabBar.swift`'s hand-built icon+label row is replaced by a stock segmented
`Picker` bound to `store.pane`, at the same padding so the rest of the layout
doesn't shift. Same 380pt width. Mock data, state model, panes, calendar,
Settings, and the thin scrollbar started out byte-identical to v2; the Services
pane has since diverged (see below).

Also carried over from v2: the window height is dynamic rather than a fixed
560pt (`PopoverView.swift`, `HeightReader.swift`), sized to whatever the
calendar and the active pane actually need, clamped to a floor and ceiling. See
v2's README for why.

## The Services pane

The one part that was designed here rather than carried over from v2, and the
part with rules worth keeping when this is rebuilt for real:

- **Every bar is measured from one line.** `PlotColumn` in `ByServicePane.swift`
  fixes an icon gutter on the left and a time gutter on the right; a service's
  own bar and its format bars are drawn against the same width, so a format's
  length can be compared against the total it is a slice of. Before this, a
  format that was two-thirds of YouTube drew at half of YouTube's bar, because
  the two sat in boxes of different widths.
- **Nesting can't break that.** Format rows step in by `PlotColumn.nest`, which
  lands their marks under the first letter of the service's name.
  `DurationBar.narrowerThanPlotBy` adds the indent back before measuring, so how
  deeply a row is nested no longer changes how long its bar draws.
- **`DurationBar.leadIn` is a deliberate hack.** A service bar paints a
  `nest`-wide run of colour backwards out of the measured line, so it *looks*
  like it starts under its own name. Every bar's right edge stays honest and
  comparable; a service bar's *length* over-reads by that constant against a
  format bar's. Read the ends, not the lengths.
- **`FormatLogo.swift`** draws videos / shorts / live as vector marks in the
  same 15pt slot `ServiceLogo` uses, traced from YouTube's own artwork on its
  48x48 grid. The names survive only as hover text.

## Status

Not production code, not wired to `WatchLogsKit`. Kept as the reference for
issue #23's real implementation in `app/Sources/WatchLogs`.
