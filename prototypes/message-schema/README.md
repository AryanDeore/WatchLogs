# Prototype: message schema — the Flush payload & Event objects

Answers wayfinder ticket [#2](https://github.com/AryanDeore/WatchLogs/issues/2) on map
[#1](https://github.com/AryanDeore/WatchLogs/issues/1).

## Question

What exactly does the Extension POST to the App on a Flush? Concretely: the envelope,
the per-View fields, every Event object, and the Ack — with types, required/optional,
and how the schema is versioned.

## Run it

Open `index.html` by double-click. No build, no server.

Drive a mock viewing session with the domain-language buttons (or the guided
walkthroughs A–E) and watch the exact JSON POST body build up on the right, alongside
the App's Ack. The field reference and the list of open design questions are on the
page itself.

## What's throwaway vs. what lifts

- **Throwaway:** the whole HTML page shell (buttons, scenario tabs, rendering).
- **Lifts into the Extension later:** the pure module at the top of the `<script>` —
  `initSession` / `apply` (the capture-side reducer) and `buildFlush` (produces the
  POST body from what the App has Ack'd). No DOM, liftable as-is.

## Guided walkthroughs

- **A · Happy path** — baseline: one clean View, one Flush.
- **B · Seek mid-play** — does one `seeked {from,to}` carry enough for Segment splitting (ticket #6)?
- **C · New video, same tab** — old View closes `video-changed`, new View starts with `previousViewId`; no `videoChange` event.
- **D · Background audio** — wire carries raw `hidden` + `sample.visible=false`; the App, not the Extension, decides "background".
- **E · Crash recovery** — `viewEnded` reason `crash-recovered`, stamped at the last `sample`, not "now".

## Status

Draft for review. Open questions 1–10 on the page are what needs a decision before this
folds into the spec.
