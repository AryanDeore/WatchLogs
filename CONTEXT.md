# WatchLogs — Context & Glossary

The ubiquitous language for WatchLogs. Use these exact terms in issues, specs, code, and
tests. This file is a glossary only — no implementation detail, no decisions. Decisions
live in `docs/adr/` and the wayfinder map (GitHub issue #1).

## Terms

### Extension

The software that runs inside a web browser and observes video playback. The only source
of data for WatchLogs. Targets Chromium-family and Firefox-family browsers; Safari is a
later phase.

### App

The macOS menu bar application. It receives data from the Extension, stores it, computes
Watched time, and displays it. One process: receiver, database, and UI together.

### Event

One recorded fact about playback at a moment in time — for example playback started,
playback paused, the user seeked, the tab became hidden. The Extension captures Events;
the App interprets them.

### Flush

One handoff of buffered Events from the Extension to the App. The Extension Flushes every
few seconds while a video plays, and again when the video ends. Events are held on disk
until the App confirms receipt.

### View

One person's engagement with one identified video, in one browser tab. Identified by
Service, video id, and tab. Video metadata — title, author, Service, content format —
attaches to the View. A new video id in the same tab ends the View and starts another.

### Capture

What the Extension is holding on behalf of the App: its open Views, the Events
recorded against them, and how far the App has acknowledged each one. A Capture
outlives the page that produced it — it is on disk — which is what lets an
unclean shutdown be recovered rather than lost.

### Segment

One continuous span of real time during which a View's Watched conditions held true. A
View has many Segments. Segments are never merged: watching the same stretch of a video
twice produces two Segments. A seek splits a Segment, so each Segment covers one unbroken
range of the video's own timeline, and records that range's start and end position.

Every Segment is either **watched** (Watched conditions held) or **background** (the
video was playing but its tab was not in the foreground). Only watched Segments add to
Watched time.

### Watched time

For a View, the sum of its Segment lengths. Cumulative: re-watched spans are counted
again. Watched conditions: the video is playing AND its tab is in the foreground. Muted
still counts. Picture-in-Picture still counts.

### Background audio

Sound from a View whose tab is not in the foreground. Recorded as **background**
Segments (see Segment). It does not add to Watched time; it is kept so analysis can
later include or exclude it.

### Day

The span of time WatchLogs files activity under, labelled by the calendar date it began.
A Day is not a fixed clock day: its boundaries flex with the user's activity and it may
run longer or shorter than 24 hours (see ADR 0001). A **frozen** Day is one whose
boundary is confirmed; its totals never change afterward. Weeks (Monday–Sunday) and
months (1st–end) are whole numbers of Days.

### Service

The video platform a View belongs to — for example `youtube`, `netflix`. For a site with
no Adapter, the Service is its domain.

### contentFormat

The kind of content and player within a Service: `short`, `standard`, or `live`. YouTube
Shorts is `service = youtube`, `contentFormat = short` — not a separate Service.

### embedded

A boolean on a View: true when the video plays inside a third-party page rather than on
the Service's own site. Independent of `contentFormat`.

### Adapter

A per-Service reader that knows how to extract a video's id and metadata from that
Service's pages. WatchLogs ships Adapters for YouTube and Netflix; other Services fall
back to generic extraction and are flagged in the App as needing an Adapter.

## Debug Tools

These are development tools that read the database but do not write to it. They answer
questions no single layer can: where did a number come from, and could this state have
physically happened.

### wl-replay

A Swift CLI tool that traces one View's complete journey through the pipeline: from the
Extension's raw Events, through the App's Segment computation, to the History row that
renders in the UI. Renders the same report in the terminal or as JSON (for the db-viewer's
Replay tab). Calls the shipped SegmentComputer and read model, never a re-implementation,
so stored-vs-recomputed comparison is meaningful: disagreement indicates the Segments were
written by an older build, not that either is wrong. See `app/Sources/WLReplay/`.

### wl-lint

A Node CLI tool that runs invariant checks over the stored database — asking not whether
each layer did what it meant to, but whether the *result* is something that could have
physically happened. Eight checks: impossible tab overlaps, phantom Watched time where the
video barely moved, Segments with duration mismatches, etc. Integrated into db-viewer's
Lint tab with the same code, so the two always agree on what they are looking at. See
`tools/lint/`.

## Terms this vocabulary avoids

- **Session** — ambiguous (browser session vs viewing session). Use **View** for
  one person's engagement with one video, and **Capture** for what the Extension
  is holding.
- **Calendar day / midnight boundary** — WatchLogs's **Day** is activity-flexed, not a
  fixed clock day; "midnight" never appears in the model.
- **Domain** — for grouping, use **Service**. "Domain" only describes the fallback case
  where a Service has no Adapter.
- **Screen time / app time** — WatchLogs measures **Watched time**, not window or app
  foreground time.
- **Unique watch time** — the earlier prototype merged re-watched spans; WatchLogs does
  not. Watched time is cumulative.
