# Prototype: pane-switcher options — v3

Answers one question pulled out of issue
[#23](https://github.com/AryanDeore/WatchLogs/issues/23): **what should the
History / By Service / Trends switcher look like?**

v1 (`prototypes/issue-23-menubar-popover/`) used flat pill tabs ported from the
HTML mockup. v2 (`prototypes/issue-23-menubar-popover-v2/`) used an icon + label
row. Neither felt settled, so this prototype does nothing but show the same
popover shell with the switcher swapped between **eight** candidates.

## Run it

```
cd prototypes/issue-23-menubar-popover-v3
swift run
```

Look for **"3"** in the menu bar (`3.circle.fill`). Use the **‹ ›** arrows in the
bottom bar to page through the variants — the rationale for whichever one is
showing sits right underneath it. `Ctrl+C` or `killall MenubarPopoverPrototypeV3`
to stop.

The pane content below the switcher is a deliberate placeholder — this prototype
is only asking about the bar. The chrome around it (title row, range presets,
summary strip) is real enough that each variant is judged in context.

## The eight options

| | Variant | The trade |
|---|---|---|
| **A** | Segmented control | Stock macOS `Picker(.segmented)`. Zero custom code, instantly familiar, inherits system behaviour. Text-only, and eats a full row of height. |
| **B** | Icon + label | What v2 ships. Scannable once learned, unambiguous selected state. Tallest horizontal option. |
| **C** | Underline tabs | Browser/Safari idiom. Very quiet — suits a panel whose content is the point. Least visible selection at a glance. |
| **D** | Pill tabs | v1's, cleaned up. Reads clearly as "selected", shorter than B. Closest to a web tab bar — the look v2 was moving away from. |
| **E** | Icon only | Most compact horizontal option; buys a whole row back. Costs discoverability — leans on tooltips. |
| **F** | Sidebar rail | Vertical, off the height budget entirely. Native (Mail/Finder), but takes ~44pt of a 380pt width the panes need. |
| **G** | Inline menu | Cheapest in space — one line, can share a row with the range label. Hides two of three panes behind a click. |
| **H** | Tiles with totals | CodexBar's provider-tile pattern; each tile carries a headline number, so the bar informs before you click. Heaviest, and its numbers compete with the summary strip above it. |

## The actual decision

The panes are switched between *constantly* — that's the core interaction, so
**G (inline menu) is likely out** despite winning on space. **F (rail)** trades a
scarce axis (width) for a plentiful one (height) in a 380pt panel, so it's a hard
sell too. That leaves the horizontal bars, where the real question is how much
vertical budget the switcher deserves: **E** (least) → **A / C / D** → **B** →
**H** (most).

## What's shared with v1 / v2

`MockData.swift` and `ServiceLogo.swift` are copied over so the shell renders the
same fictional August 2026 numbers and the same service marks. `Pane` lives in
`SwitcherVariants.swift` here rather than `MockData.swift`, since it's the thing
under test and carries extra affordances (short labels for tight variants).

## Status

Not production code. Pick a variant here, then fold it back into whichever of
v1/v2's chrome direction wins for issue #23's real implementation.
