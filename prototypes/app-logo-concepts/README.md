# Prototype: app logo concepts

Two sketches for a WatchLogs app icon / menu-bar mark, drawn as vector shapes
the same way `ServiceLogo.swift` (in the menubar-popover prototypes) draws the
Netflix/Twitch/YouTube marks — plain SwiftUI `Shape`s, not artwork.

## Run it

```
cd prototypes/app-logo-concepts
swift run
```

A gallery window shows both concepts at app-icon size (160pt) and menu-bar
size (16pt), each on a light and a dark tile.

## The two concepts

**A — logs + watch** (`LogPlayMark`). Three horizontal bars — read as log/list
entries — left-aligned with their right edges stepped out to a point, so the
same three strokes double as a play-triangle silhouette. Cheap dual reading:
"a list of watch-log entries" and "press play." At small sizes it reads more
as a generic sort/filter glyph than an explicit play button — worth deciding
if that ambiguity is acceptable or if the taper needs to be sharper.

**B — Watch_Dogs mark** (`WatchDogsMark`). A circle with two flanking pillars
and a woven hourglass/bowtie between them — a loose vector approximation of
Ubisoft's Watch_Dogs logo, not a trace of it, picked for the pun (WatchLogs /
Watch Dogs). Holds up better at menu-bar size than concept A — the ring plus
crossing diagonals stay legible as a distinct shape even at 16–28pt.

## Status

Sketches for discussion, not a final asset. Whichever direction wins should
be redrawn/refined (and checked against Ubisoft's trademark before shipping
anything this close to their mark) rather than shipped as-is.
