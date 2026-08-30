# Prototype: menubar layout — range selector + History / By Service / Settings

Answers wayfinder ticket [#7](https://github.com/AryanDeore/WatchLogs/issues/7) on map
[#1](https://github.com/AryanDeore/WatchLogs/issues/1).

## Question

How is the menubar popover laid out? One shared date-range selector over three v1
panes (History, By Service, Settings), a reserved slot for the future Categorical
pane, and two decisions that hang on the layout: **popover size limits** and
**fixed vs resizable**.

## Run it

Open `index.html` by double-click. No build, no server.

The page renders the popover hanging off a faux macOS menubar so you can judge it
at real density. Flip between three layouts with the floating bar at the bottom,
the `←` / `→` arrow keys, or `?variant=A|B|C` in the URL.

Everything is wired: the range selector (including the Custom month grid — click a
start day, click an end day, Apply), collapsing day groups, the YouTube
`contentFormat` expander, the Settings slide-over (variant B), and a working
drag-resize corner (variant B). Mock data only.

## The three layouts

They disagree about **structure**, not colour.

- **A · Compact tabbed** — 360 × 520, **fixed**. Classic menubar popover. Range
  selector pinned in the header; one pane at a time behind a tab row; Settings is
  a gear; Categories is a disabled tab. Smallest footprint, one tap to any pane,
  but you never see two panes together.
- **B · Single scroll** — 420 × 600, **resizable** (drag the corner). No tabs:
  History, By Service and a Categories stub are one continuous scroll under a
  sticky range header. Settings slides over from the right. Best for "what did I
  watch" at a glance; worst for a deep By-Service dive.
- **C · Master / detail** — 560 × 640, **fixed**, window-like. Left rail holds the
  range control and a vertical nav (History / By Service / Categories 🔒 /
  Settings); the right pane gets room to breathe — By Service becomes a real bar
  chart with the YouTube split as nested bars. Most capable, least "menubar-y".

## Day-boundary inputs folded in

From [ticket #8](https://github.com/AryanDeore/WatchLogs/issues/8) (resolved), all
three variants show:

- **A day that ran past midnight** — Monday Aug 25 is one group with a
  `9:04 AM → 3:12 AM (+1d)` caption; a 1:40 AM View sits under Monday, not Tuesday.
- **Provisional "Today"** — lighter-weight total, a `counting` pill, and a note
  that it re-files at ~04:00. Nothing implies the number is final.
- **"My day ends around ___"** — a Settings control, default 04:00. The 10:00 hard
  cap is not shown.
- **Range presets** — Today / This Week (Mon–today) / This Month (1st–today) /
  Custom. Presets switch instantly; Custom shows a brief spinner.

## What's throwaway vs. what lifts

- **Throwaway:** the whole HTML page, all three variant renderers, the faux
  menubar shell, the switcher bar, the mock data.
- **Lifts into the App later:** none of the code. What lifts is the **decision** —
  the chosen structure, size, and fixed/resizable call — captured in `LAYOUT.md`
  and folded into the spec.

## Status

Draft for review. `LAYOUT.md` lists what each variant proposes and the open
questions that need Aryan's call before this folds into the spec. **Not resolved
yet** — this is a HITL ticket; it closes after the live reaction.
