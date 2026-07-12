# WatchLogs — Product Requirements Document

**Version:** 0.2 — Now Playing architecture pivot  
**Status:** In planning  
**Last updated:** June 2026

---

## 1. Why we are building this

We want accurate insight into how much time we actually spend watching videos — not just which websites are open.

---

## 2. What we are building (updated)

WatchLogs is now a **pure macOS application** that tracks video watch time using the system Now Playing API.

### Components

1. **Swift menu bar app (primary + only component)**
   - Polls macOS Now Playing API
   - Tracks playback state and time
   - Stores data locally in SQLite
   - Renders UI in menu bar

---

## 3. Key architectural decision (major change)

### Dropped: Go daemon

- No background Go service
- No HTTP API
- No browser extension

### Adopted: Now Playing polling

We use macOS media APIs (Now Playing / MediaRemote) as the source of truth.

---

## 4. Core tracking model

### Single-source tracking

We explicitly track:

> **Only the active Now Playing session**

We do NOT attempt to:
- track multiple simultaneous videos
- track background tabs

---

## 5. Polling architecture

### Polling interval

Every **2 seconds**

### Data fetched per poll

We combine two system frameworks:

- MediaPlayer framework → Now Playing (media data)
  - title (video title)
  - elapsedTime (current playback position)
  - playbackRate (0 = paused, 1 = playing)
  - duration (if available)

- AppKit framework → NSWorkspace (app context)
  - bundleID (which app: Chrome, Safari, etc.)

Note: Now Playing does NOT reliably provide the source app, so NSWorkspace (AppKit) is used to infer the active media source.

---

### Core loop logic

Every 2 seconds:

1. Fetch Now Playing info
2. Fetch active app via NSWorkspace
3. Create an abstraction layer object (NowPlayingSnapshot)
   - typed fields: title, elapsedTime, duration, playbackRate, bundleID
   - hides raw dictionaries and casting from the rest of the app
4. Pass snapshot to tracking engine

Note: All Apple framework interactions (MediaPlayer + AppKit) are isolated to snapshot creation.
---

### State handling rules

#### Rule 1 — Ignore paused media

If:
- playbackRate == 0

→ Do nothing

---

#### Rule 2 — Detect new video

If:
- title changes OR
- bundleID changes

→ Close current session
→ Start new session

---

#### Rule 3 — Track playback progression

Compare previous elapsedTime with current:

- Small forward increase → normal playback
- Large jump forward → seek detected
- Decrease → rewind or new session

---

### Segment model

We still use **watched segments**:

- Each continuous playback range is a segment
- Segments are merged to compute unique watch time

Accuracy:
- ±2 seconds (polling granularity)

---

## 6. Trade-offs of this architecture

### What we gain

- Works across all browsers automatically
- No extension required
- Much simpler system
- Faster to build and iterate

### What we lose

- No video URL
- No stable video ID
- No Shorts detection
- Cannot track multiple simultaneous videos

---

## 7. Identity model (important constraint)

We do NOT have a true video ID.

Instead:

- Title is primary identifier (imperfect)
- We may generate a **derived ID** using:
  - title
  - duration

Sessions remain uniquely identified by timestamp.

---

## 8. Data model

### sessions

Source of truth for viewing activity.

Fields:
- id (TEXT, PK, UUID)
- title (TEXT)
- bundle_id (TEXT)
- started_at (TIMESTAMP)
- ended_at (TIMESTAMP)
- duration_sec (REAL) — merged unique watched time
- duration_total (REAL, nullable)

---

### watched_segments

Raw contiguous playback ranges within a session.

Fields:
- id (INTEGER, PK, AUTOINCREMENT)
- session_id (TEXT, FK → sessions.id)
- start_sec (REAL)
- end_sec (REAL)

---

## 9. Build phases (updated)

### Phase 1 — Core tracking (Swift only)

- Poll Now Playing
- Detect sessions
- Track segments
- Store in SQLite

### Phase 2 — UI

- Menu bar app
- Today summary
- Recent sessions

### Phase 3 — Improvements

- Categorization
- Better grouping heuristics

---

## 10. Open questions

- Best strategy for grouping sessions into videos?
- Should we keep a videos table or compute on the fly?
- How to handle title collisions?

---

## 11. Performance validation

Before release, validate real-world resource usage and document results.

Requirements:
- Measure CPU usage
- Measure memory (RAM) usage
- Measure energy impact / battery usage
- Observe behavior during active playback and idle states

Deliverables:
- Capture screenshots from Activity Monitor (CPU, Memory, Energy tabs)
- Include representative scenarios (idle, active video, switching apps)
- Add screenshots and a short summary to the GitHub README

Goal:
- Ensure the app behaves as a low-overhead background utility on both Intel and Apple Silicon Macs

---
