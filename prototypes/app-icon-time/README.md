# Prototype: app icon + running watched time

**Question.** The shipped menu-bar mark (the stepped log/play bars, Concept A
from `prototypes/app-logo-concepts`) stays. What should it look like once it
*also* carries a running watched-time readout — bare minutes under an hour,
`H:MM` at or over an hour?

Ten variants, switchable, live in the real menu bar and side by side in a
gallery window.

## Run it

```
cd prototypes/app-icon-time
swift run
```

A status item appears in the menu bar and a gallery window opens. In the
gallery: drag **Watched time** to scrub the readout, or flip **Simulate
watching** to make it tick up (sped up 60x). Each variant is shown on a light
tile, a dark tile, and at 2x. "Show in menu bar" / the popover picker swaps
which one is live in the status item.

> Throwaway. No persistence, no real event data — the watched-time value is a
> wall-clock sim. The marks are the same hand-drawn `Shape`s as the other logo
> prototypes, not final artwork.

## The ten variants

| # | Name | Idea |
|---|------|------|
| 1 | Inline trailing | Mark, one space, monospaced-digit time. The obvious baseline. |
| 2 | Time only | No mark in the bar — just the number; the mark lives in the popover. Does the glyph still earn its pixels? |
| 3 | Reversed pill | Time knocked out of a filled accent capsule with a tiny mark prefix. Reads as a status badge. |
| 4 | Stacked micro | Two lines in 22 pt: a 6-pt WATCHED label over the time, mark to the left. Deliberately cramped. |
| 5 | Mark as separator | The play mark stands in for the colon: `1 ▷ 05`. Plain minutes under an hour. |
| 6 | Goal ring | Progress ring (fraction of a daily goal) around a mini mark, time trailing. Adds a second data dimension. |
| 7 | Unit suffixed | `47min` / `1h05`, unit in a lighter weight. Words instead of punctuation. |
| 8 | LCD stopwatch | Seven-segment-ish green digits on a dark plate, bracketed, no mark. "A stopwatch is running." |
| 9 | Live dot | Mark + time with a dot between: red while actively watching, grey when idle. Shows counting vs paused. |
| 10 | Blinking colon | Width-locked `1:05`; the colon blinks once a second while counting. The blink is the identity. |

## Things to decide by looking

- Does keeping the mark alongside a number still read, or does variant 2 win by
  subtraction?
- The mark shrinks to 7–9 pt in variants 5 and 6 — its 15%-height bars nearly
  vanish. Acceptable, or does the mark need a heavier small-size cut?
- Minutes-only vs always-`H:MM`: variants 1/2/7/9 follow the "(MM, HH:MM)"
  rule; 8 and 10 always show a colon. Which feels less jumpy as it crosses the
  hour?
- Width stability. Only variant 10 is explicitly width-locked. Watch the others
  reflow the menu bar as digits change.
- Colour in the menu bar (3, 6, 8, 9) vs template monochrome (the rest).

## Status

Sketches for discussion. The winner gets redrawn properly and folded into
`WatchLogsApp.swift` (`MenuBarExtra { … } label:`), which today renders a plain
`Image(nsImage: .logPlayMarkTemplate())` with no text.
