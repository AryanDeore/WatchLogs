

> **Now Playing → tracking engine → storage → UI**

## step 1 — probe the Now Playing API (exploration phase)

your idea is correct, but keep it lightweight:

goal:
- print raw Now Playing data every 2s

combine two sources:
- Now Playing → media data
- NSWorkspace → active app (bundleID)

don’t build structure yet, just log:

- title  
- elapsedTime  
- playbackRate  
- duration
- bundleID (from NSWorkspace)  

you’re answering:
> “what does the data actually look like in real life?”

test cases:
- YouTube
- Netflix
- pause/play
- switching apps

---

## step 2 — create abstraction layer (NowPlayingSnapshot)

before building tracking logic, create a clean abstraction over system APIs

create a Swift struct:

`NowPlayingSnapshot`

responsibility:
- combine MediaPlayer (Now Playing) + AppKit (NSWorkspace)
- convert raw `[String: Any]` into typed fields
- hide casting and Apple-specific keys

fields:
- title
- elapsedTime
- duration
- playbackRate
- bundleID

verify by printing clean snapshots every 2s

---

## step 3 — build the tracking engine (MOST IMPORTANT)

this is your real “backend”

create a Swift class like:

`PlaybackTracker`

responsibility:
- hold current state
- compare previous vs current snapshot
- emit:
  - new session
  - segment start/end
  - seek detected

don’t touch SQLite yet

just:
- print events like:

```
START SESSION: "How to learn Go"
SEGMENT: 120 → 140
SEEK detected
END SESSION
```

---

## step 3 — implement segment logic

this is the hardest/most valuable part

handle:

- normal playback
- pause/resume
- seek forward
- seek backward
- video change

once this works:
> your core product is basically done

---

## step 4 — add SQLite persistence

now connect:

tracker → database

rules:

- session start → insert session
- segment end → insert segment
- session end → update duration

keep it simple:
no optimization yet

---

## step 5 — build minimal UI (don’t overdo SwiftUI yet)

start with:

- total time today
- list of sessions

even a basic list is fine

goal:
> verify data is useful, not pretty

---

## step 6 — refine UI

only now:

- menu bar popover
- categories (optional)
- nicer layout

---

# your updated roadmap (clean version)

1. **Now Playing probe**
   - print raw data every 2s

2. **Tracking engine (core logic)**
   - detect sessions + segments
   - print events

3. **Segment correctness**
   - handle seeks, pauses, switches

4. **Persistence (SQLite)**
   - store sessions + segments

5. **Basic UI**
   - display today’s data

6. **Refinement**
   - polish + categorization
