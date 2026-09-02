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
| Day / YouTube-split expand-collapse | Custom chevron + manual `collapsedDays` state | `DisclosureGroup` was tried and pulled back out — see below |
| Trends, > 14 days | Hand-rolled columns via `GeometryReader` | **Swift Charts** (`Chart`, `BarMark`) — stacking and axis thinning from the framework |
| Trends, ≤ 14 days | Hand-rolled label \| track \| value rows | **Kept v1's layout** — Swift Charts was tried and pulled back out (see below) |
| Settings | Custom `.field`/`.set` div-alikes | Native `Form` + `.formStyle(.grouped)` + `LabeledContent`/`Toggle`/`Stepper` — the same layout engine as System Settings panes |
| Service icons | Coloured mono initials (`Y` / `N` / `T`) | Drawn brand marks (`ServiceLogo.swift`) — YouTube play badge, Netflix N, Twitch glitch |
| Scrollbar | Stock overlay scroller | Custom ~2.5pt knob (`ThinScrollView.swift`), roughly a third the stock width |
| Typography | Fixed px sizes ported from CSS, heavy use of monospaced digits | System text styles (`.headline`, `.callout`, `.caption`) with `.monospacedDigit()` only on numeric readouts |

Four components are **not** fully native, each for a specific reason:

- **Calendar** — `DatePicker` selects a single date and can't render a connected
  range highlight across a week/month grid, which Today/Week/Month/Custom needs.
  Reskinned with system colors/fonts, but structurally still v1's grid.
- **Expand/collapse rows** — `DisclosureGroup` only hit-tests its triangle, so a
  header row reading "Thursday Aug 28 … 3h 32m" was only clickable on a 10pt
  chevron. Replaced with a plain `Button` over the whole row plus
  `.contentShape(Rectangle())`, keeping the chevron as a rotation affordance.
- **Trends at ≤ 14 days** — Swift Charts was built here first and removed. At
  popover width its categorical y-axis labels overlapped the bars, the plot border
  and gridlines added clutter a 380pt panel can't afford, and a raw "minutes"
  x-axis reads worse than just printing `3h 32m` at the end of each row. v1's
  fixed-label / full-width-track / value-column layout was cleaner, so it's back —
  with native type and colors. Swift Charts still owns the > 14-day case, where
  individual rows stop being readable anyway.
- **Scrollbar** — AppKit exposes no knob-width setting, so the system indicator is
  hidden and a thinner one drawn over it. `.scrollIndicators(.hidden)` alone does
  not do it: the overlay scroller still faded in on hover, so a small
  `NSViewRepresentable` reaches `enclosingScrollView` and clears
  `hasVerticalScroller`.

### On the logos

The marks are drawn as vectors rather than shipping trademarked artwork into the
repo; a real build should use each service's official asset under its brand
guidelines. Note the tension they introduce: the logos are brand-accurate, so
**YouTube and Netflix are both red**, while the charts keep the legibility palette
(Netflix = amber) so stacked bars stay readable. Identity marks next to a text
label can afford to collide; comparison bars can't. Worth an explicit decision
before this ships.

## Findings

- **Native isn't automatically better at popover scale.** Swift Charts won on the
  dense >14-day view and lost on the ≤14-day one; a 380pt panel doesn't have room
  for a general-purpose chart's axes, gridlines, and border. The hand-rolled rows
  from v1 stayed cleaner. Reach for the framework, but measure at real width.
- `ProgressView(value:)` is a direct, no-compromise replacement for v1's
  `GeometryReader` fill bars. `DisclosureGroup` is not: its label is inert, so any
  row where the whole strip should be the target has to be a `Button` instead.
- `Form` + `.formStyle(.grouped)` gets Settings most of the way to looking like a
  real System Settings pane for free — no custom `.field` layout needed. Settings
  is swapped in for the panes (`if/else` in the `ZStack`) rather than layered over
  them: layering forces an opaque background of its own, which then visibly fails
  to match the popover's vibrancy material.
- A default-alignment `VStack` silently indents its short children. Rows with a
  full-width `ProgressView` stretched to the panel edge while live rows (no known
  length, so no bar) centred themselves — reading as if live views were nested one
  level deeper. `VStack(alignment: .leading)` everywhere, and a `Spacer` before
  each duration so they share a right edge.
- Two sibling `ForEach`es in one `LazyVGrid` must not share ids. The month grid's
  leading blanks used `0..<lead` and its days used `1...dim`; the overlap made the
  first few days of every month vanish, differently per launch.
- Stock overlay scrollers are sized for document windows and read as heavy in a
  popover, and AppKit gives no width knob — a custom indicator is the only route.
  Hiding the stock one is a two-step job: `.scrollIndicators(.hidden)` suppresses
  it at rest but it still fades in on hover, track and all, so the custom knob
  ends up sitting on top of a second, wider bar.
- Same `Color`-vs-`ShapeStyle` friction as v1 (`.tertiary` on a `Color`-typed
  ternary branch needs an explicit `Color(nsColor: .tertiaryLabelColor)`).
- A fixed 560pt window height meant Custom's expanded month grid (~190pt) could
  crowd out a 14-day Trends chart enough to force scrolling to see the last few
  bars. Fixed to window content instead of a fixed frame: `ThinScrollView`
  already measured its own content height for the knob math
  (`ThinScrollView.swift`), so that value is now piped up via a callback and,
  combined with a `measureHeight` on the chrome above it (`HeightReader.swift`),
  drives the window's height directly — clamped to a floor (so a near-empty pane
  doesn't shrink to a sliver) and a ceiling read from `NSScreen.main`'s visible
  height, past which `ThinScrollView` still scrolls, same as before. This
  responds to *any* pane's content, not just the calendar — a short History list
  now shrinks the window too.
- **A preference set inside `.background` does not propagate out to an
  `.onPreferenceChange` on the modified view.** The first version of
  `measureHeight` was a `PreferenceKey` in a `.background` `GeometryReader`; it
  silently reported `0` forever, so the window got sized as though the entire
  header (title, range presets, calendar, summary strip, tab bar — 364pt with the
  month grid open) had no height, and the chart stayed cut off. Nothing errors and
  nothing logs; the value is just always the default. `GeometryReader` +
  `onAppear`/`onChange` callbacks work fine in the same position, which is what
  `ThinScrollView` was already doing — worth copying the shape that demonstrably
  works rather than reaching for preferences.
- `MenuBarExtra(.window)` **does** honour a dynamic `.frame(height:)` — the panel
  tracks it. Verified by instrumenting the hosting `NSWindow`: with the header
  measured correctly, a Custom 14-day range on Trends reports chrome 364 + pane
  303 = 667, and the window is 667.
- The pane switcher stayed unsettled through both versions — pulled out into its
  own prototype, `prototypes/issue-23-menubar-popover-v3/`.
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
