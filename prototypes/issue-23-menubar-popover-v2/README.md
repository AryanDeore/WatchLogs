# Prototype: menubar popover, v2 — native macOS chrome

Answers issue [#23](https://github.com/AryanDeore/WatchLogs/issues/23) (slice 6 of
the [tracer-bullet build](https://github.com/AryanDeore/WatchLogs/issues/18)).
Second iteration on top of `prototypes/issue-23-menubar-popover/` (v1) — v1 stays
as-is, untouched, for comparison.

## Question

v1 ported the converged HTML mockup (`prototypes/menubar-layout/`, issue
[#7](https://github.com/AryanDeore/WatchLogs/issues/7)) close to 1:1 — same custom
hex palette, same flat pill buttons and hand-drawn bars. It compiled and ran as a
real `MenuBarExtra` popover, but it reads as "a web page in a window," not a native
macOS menu-bar utility. This prototype asks: **keep the same information
architecture** (title row, range selector, calendar, summary strip, History / By
Service / Trends, Settings) but **rebuild the chrome out of native macOS idioms** —
does it read like a real menu-bar app this way? Reference: apps like
[CodexBar](https://github.com/steipete/CodexBar) — vibrancy material, plain system
typography, native controls, a real menu-list footer.

## Run it

```
cd prototypes/issue-23-menubar-popover-v2
swift run
```

Look for a **"2"** in the menu bar (`2.circle.fill`). Versions are numbered so v1,
v2, (v3, ...) can all run at once and stay distinguishable: v1 is "1", this one is
"2". `Ctrl+C` or `killall MenubarPopoverPrototypeV2` to stop it.

## What's the same as v1

Identical mock dataset and state model (`MockData.swift`, `PopoverStore.swift` —
copied over, not re-derived) and the same round-5 information architecture: fixed
popover, preset-driven range across three panes, calendar collapsed to a week row
except under Custom, top-3 summary strip, History/By Service/Trends, Settings as a
slide-over. If v1's layout decisions are wrong, this prototype won't tell you that —
it only tests whether *native chrome* changes the verdict.

## What's different — native replacements, one per component

| Component | v1 (HTML-ported) | v2 (native) |
|---|---|---|
| Popover background | Flat white (`--card`) | `.regularMaterial` vibrancy — desktop bleeds through, like CodexBar |
| Range presets | Custom pill buttons, hand-drawn borders | `Picker(...).pickerStyle(.segmented)` — the actual macOS segmented control |
| Pane switcher | Custom flat tab pills | Icon + label tab row (CodexBar's provider-switcher pattern): SF Symbols, accent-filled selected state |
| Calendar | Custom grid, hex accent blue, monospace digits | Same custom grid (kept — see below), but `Color.accentColor`/`.primary`/`.secondary`/`.tertiary`, system font |
| Coverage bar / part-to-whole bars | `GeometryReader` + manual `Capsule` fills | `ProgressView(value:).tint(...)` — native linear progress control |
| Day / YouTube-split expand-collapse | Custom chevron + manual `collapsedDays` state | `DisclosureGroup` — the native SwiftUI/AppKit disclosure triangle |
| Trends chart | Hand-rolled bars via `GeometryReader` | **Swift Charts** (`Chart`, `BarMark`, `.chartForegroundStyleScale`) — same framework Screen Time/Fitness/Stocks use; stacking, axis thinning, and the legend are the framework's, not hand-written |
| Settings | Custom `.field`/`.set` div-alikes | Native `Form` + `.formStyle(.grouped)` + `LabeledContent`/`Toggle`/`Stepper` — the same layout engine as System Settings panes |
| Typography | Fixed px sizes ported from CSS, heavy use of monospaced digits | System text styles (`.headline`, `.callout`, `.caption`) with `.monospacedDigit()` only on numeric readouts |

The calendar is the one component **not** swapped for a fully native control:
`DatePicker` selects a single date and can't render a connected range highlight
across a week/month grid, which Today/Week/Month/Custom needs. It's reskinned
(system colors/fonts, `Color.accentColor`) but structurally still the v1 grid.

## Findings

- Swift Charts is the standout: stacking, legend placement, and (for the >14-day
  vertical case) axis-label thinning on dense data all come from the framework
  instead of hand-written arithmetic. Far less code than v1's `TrendsPane.swift`.
- `DisclosureGroup` and `ProgressView` are direct, no-compromise replacements for
  v1's hand-rolled collapse/expand chevrons and `GeometryReader` fill bars.
- `Form` + `.formStyle(.grouped)` gets Settings most of the way to looking like a
  real System Settings pane for free — no custom `.field` layout needed.
- Same `Color`-vs-`ShapeStyle` friction as v1 (`.tertiary` on a `Color`-typed
  ternary branch needs an explicit `Color(nsColor: .tertiaryLabelColor)`).
- Verified with `swift build` (clean) and a `swift run` smoke test (launches,
  stays alive, no crash). Visual comparison against v1 (and the HTML) is a manual
  step — automated screenshotting hit a Spaces issue in this environment (the
  terminal runs full-screen in its own Space, and `screencapture` only captures
  the active Space, so a freshly launched menu-bar app's window/popover in another
  Space doesn't show up even with Screen Recording permission granted). Run both
  prototypes side by side to compare directly.

## Status

Not production code, not wired to `WatchLogsKit`. Compare this against v1 and the
original HTML (`prototypes/menubar-layout/`) to decide which chrome direction
issue #23's real implementation (`app/Sources/WatchLogs`) should take.
