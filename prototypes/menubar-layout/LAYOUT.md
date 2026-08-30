# Menubar layout — what each variant proposes, and the open questions

Companion to `index.html`. This is the material for the HITL reaction on ticket
[#7](https://github.com/AryanDeore/WatchLogs/issues/7); it is **not** a decision.

## The scenario this has to survive

It's Friday 9:41 PM. Aryan opens the popover to answer three questions in one
glance:

1. *What did I watch tonight, and yesterday?* → History
2. *Where is my time going this week — how much of it is YouTube Shorts?* → By Service
3. *Nothing today; I just want to bump the retention window.* → Settings

...and a fourth that only matters once a month: *last Monday I coded from 9 AM
straight through to 3 AM — did that land as one day or get sliced at midnight?*

## Side-by-side

| | **A · Compact tabbed** | **B · Single scroll** | **C · Master / detail** |
|---|---|---|---|
| Size | 360 × 520 | 420 × 600 (start) | 560 × 640 |
| Resize | fixed | **user-resizable**, 320–640 × 360–760 | fixed |
| Panes | one at a time (tab row) | History + By Service stacked; Settings slides over | one at a time (left-rail nav) |
| Range selector | pinned segmented control in header | sticky segmented control, scrolls with nothing | compact button in the rail, opens grid/presets |
| Get to Settings | gear icon → replaces pane | gear icon → slide-over panel | rail nav item |
| Categories slot | disabled tab, `SOON` | dashed stub at bottom of scroll | rail nav item, 🔒 |
| By Service detail | list + thin bars, text-only `contentFormat` split | same as A | **bar chart**, `contentFormat` as nested bars |
| Feels like | a menubar utility (iStat Menus, Bartender) | a notification-center widget | a small standalone window |

## Open questions for Aryan

1. **Size ceiling.** AppKit's `NSPopover` has no hard width limit, but menubar
   convention sits ~320–420 pt wide. A (360) and B (420) are in that band; C (560)
   reads as a window, not a menu. Is the extra room in C worth breaking the
   convention, or is By-Service detail better served by keeping it narrow and
   letting it scroll?

2. **Fixed vs resizable.** Peer menubar apps are almost all fixed. Resizable (B)
   costs: a persisted size, a min/max, reflow testing at every width, and a
   drag handle that competes with the popover's own resize affordance on macOS
   (there isn't one by default). Worth it, or is "fixed width + height that grows
   with content up to a max, then scrolls" enough?

3. **One pane at a time, or stacked?** A and C hide two of the three panes behind
   a click. B shows History and By Service together but pushes Settings out of the
   way. Which matches how you'd actually use it — jump between panes, or scan them
   as one feed?

4. **Where does the range selector live when it has to coexist with a Custom
   grid?** In A/B the grid drops from a pinned header (fine at 360–420 wide). In C
   it drops from the rail. Any preference for the grid being inline vs a separate
   sheet?

5. **Categories slot.** Disabled affordance now (A's tab, C's nav row) advertises
   the future pane and reserves its spot. B's dashed stub does too but eats scroll
   height. Keep a visible placeholder, or leave it out of v1 entirely and add it
   when it ships?

6. **By Service — chart or list?** Only C commits to a chart. The `contentFormat`
   split + `embedded` sub-line is readable as text (A/B) but a chart (C) makes
   "how much is Shorts" instant. Does that view justify the width it needs?

7. **Provisional "Today" treatment.** All three use: lighter total + `counting`
   pill + "re-files at ~04:00" note. Is that clear enough that the number isn't
   final, or does it need to be more explicit (e.g. no number at all until the
   day closes)?

## A starting recommendation (to react against, not adopt)

**B's information model on A's footprint.** Keep the popover fixed and ~400 pt
wide. Stack History and By Service the way B does so the two "where did my time
go" questions share one glance, keep Settings behind a gear as a slide-over, and
carry C's little bar chart into the By Service section (it fits at 400 if the
nested bars are compact). Reserve the Categories slot as a disabled header
affordance, not a scroll-height-eating stub. Skip user-resizing; let height grow
with content to a cap, then scroll.

One-line why: the primary job is *scanning* three cheap panes, not *operating* a
dense one — that favours a stacked scroll at menubar width over either a
tab-switch or a window-sized two-pane.
