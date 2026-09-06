# Day Boundary Bug Analysis - September 6, 2026

## The Problem

Yesterday's day (2026-09-05) was frozen at **4:00:00 AM** instead of sliding to **6:12:03 AM** (90 minutes after the last activity at 4:42:03 AM).

## Timeline of Events

### Activity Before 4 AM
- Last segment starting before 4 AM: `03:59:59 -> 04:00:05` (crosses the 4 AM boundary)

### Activity After 4 AM  
- `04:00:05 -> 04:00:11`
- `04:00:11 -> 04:00:16`
- ... continuous segments ...
- `04:01:13 -> 04:03:34`
- `04:03:34 -> 04:03:48` (last segment in this burst)

**Gap #1**: 4:03:48 to 4:17:00 (13 minutes - not enough for 90-minute threshold)

### More Activity After Gap
- `04:17:00 -> 04:17:14`
- `04:17:23 -> 04:17:52`

**Gap #2**: 4:17:52 to 4:23:40 (about 6 minutes)

- `04:23:40 -> 04:23:43`
- `04:23:45 -> 04:24:14`

**Gap #3**: 4:24:14 to 4:32:19 (about 8 minutes)

- `04:32:19 -> 04:32:32`
- ... more segments ...
- `04:41:58 -> 04:42:03` (LAST ACTIVITY)

### When Should the Day Have Ended?

According to ADR 0001:
1. ✅ Activity was in progress at 4:00 AM (segment from 3:59:59 to 4:00:05)
2. ✅ Day should slide to 90 minutes after the last watched activity
3. ✅ Last activity ended at: `04:42:03`
4. ✅ Day should end at: `06:12:03` (4:42:03 + 90 minutes)

### What Actually Happened

The day was frozen at `04:00:00` exactly, as shown in `rolled_day`:
```
2026-09-05|2026-09-05 04:00:00|2026-09-06 04:00:00
```

## Root Cause Analysis

### Hypothesis 1: Backlog Draining Check

The `backlogIsDraining` check prevents day boundary detection when:
- A flush arrived within 15 seconds (ingestActiveWindowMs)
- BUT the newest activity is more than 2 minutes old (ingestCaughtUpMs = 120 seconds)

This is designed to prevent premature boundary decisions when events are still being processed.

**Problem**: When the boundary check finally ran (after the backlog cleared), the logic may have incorrectly concluded there was no activity at 4 AM.

### Hypothesis 2: Timing of `advanceOpenDay` Calls

Looking at flush times:
- Flushes continued regularly every 5-30 seconds from 4:00 through 4:42
- Last activity: 4:42:03 AM
- Flush times after last activity: 4:43:42, 4:44:12, 4:44:41...

The system would have been in "backlog draining" mode until about **4:44:03** (2 minutes after last activity).

**Critical moment**: When `advanceOpenDay` was first called after 4:44:03:
- "now" would be >= 4:44:03
- It would call `watchedIntervals(since: dayStart.epochMillis)` which is `since: 2026-09-05 04:00:00`
- This would return ALL segments ending after 4:00 AM

### Hypothesis 3: The Actual Bug

Looking at `DayBoundary.confirmedEnd` logic:

```swift
let relevant = merged.filter { $0.end > target }
guard let first = relevant.first, first.start <= target else {
    // No watched-time activity at the target hour
    return target
}
```

**The bug**: The condition is `first.start <= target`

For target = 4:00:00 AM:
- We need a segment where `start <= 04:00:00` AND `end > 04:00:00`
- The segment `03:59:59 -> 04:00:05` satisfies this: start (03:59:59) <= target (04:00:00)

So this should work correctly...

### Hypothesis 4: Provisional Segments Issue

Let me check if segments were marked as provisional:

```sql
SELECT provisional FROM segments WHERE wall_start_ms >= 1788681000000 LIMIT 5;
```

If segments crossing 4 AM were still provisional when the boundary check ran, they might have been excluded from the calculation.

### Hypothesis 5: The Real Bug - Early Freeze

**Most Likely Scenario**:

The day was frozen **before** all the activity after 4 AM was recorded. Here's what probably happened:

1. At some point between 4:00 and 4:42, the app performed an `advanceOpenDay` check
2. At that moment, it only saw activity up to, say, 4:03:48
3. The backlog draining check returned FALSE (thinking the backlog was caught up)
4. DayBoundary calculated that with activity up to 4:03:48, and "now" being >= 5:33:48 (90 min after 4:03:48), the day should end
5. The day was frozen at some calculated boundary
6. **Later segments after 4:03:48 arrived but couldn't un-freeze the already frozen day**

But wait - the `rolled_day` shows it was frozen at exactly 4:00:00, not after the activity...

## The Smoking Gun

Looking at the `rolled_day` table:
```
2026-09-05|2026-09-05 04:00:00|2026-09-06 04:00:00
```

The day ended at **exactly 4:00:00**, which means:
- The boundary logic concluded there was **NO activity at the target hour**
- It returned `target` (4:00 AM) instead of sliding

This can only happen if:
1. When `DayBoundary.confirmedEnd` was called, the intervals passed to it did NOT include the segment `03:59:59 -> 04:00:05`
2. OR there's a bug in the merge/filter logic

### Testing the Merge Logic

The `watchedIntervals(since:)` function queries:
```sql
SELECT wall_start_ms, wall_end_ms FROM segments 
WHERE kind = 'watched' AND wall_end_ms > ? 
ORDER BY wall_start_ms
```

For `since: 1788595200000` (2026-09-05 04:00:00):
- It should return segments where `wall_end_ms > 1788595200000`
- The segment `03:59:59 -> 04:00:05` has `wall_end_ms = 1788681605293`
- This IS > 1788595200000, so it should be included

Wait - I see the issue! Let me check the actual dayStart:

The `open_day` shows:
```
day_start_ms = 1788595200000 = 2026-09-05 04:00:00
```

But the previous day (2026-09-05) should have started at 2026-09-05 04:00:00 and the query is asking for segments after that timestamp.

Let me recalculate: `1788595200000 ms` = September 5, 2026 at 04:00:00 AM
And `1788681600000 ms` = September 6, 2026 at 04:00:00 AM

So the day that started at Sept 5 04:00 should have been checked for boundary at Sept 6 04:00.

The segment `03:59:59 -> 04:00:05` on Sept 6 has:
- `wall_start_ms = 1788681599439` (Sept 6, 03:59:59)
- `wall_end_ms = 1788681605293` (Sept 6, 04:00:05)

The query `watchedIntervals(since: 1788595200000)` would include this segment since its `wall_end_ms` (1788681605293) > dayStart (1788595200000).

## Root Cause - CONFIRMED

### The Smoking Gun

The critical segment `03:59:59 -> 04:00:05` (which crosses the 4 AM boundary) was NOT flushed until **04:00:36**.

But a flush arrived at **04:00:31** that triggered `advanceOpenDay`, and at that moment:
- The crossing segment did NOT exist in the database yet
- The newest activity on record was around 03:59:59
- The backlog draining check PASSED (returned FALSE), thinking the backlog was caught up
- `DayBoundary.confirmedEnd` saw no activity crossing 4 AM
- The day was frozen at exactly 4:00:00 AM

### Why the Backlog Check Failed

At 04:00:31:
- `lastFlushMs` = 1788681631618 (04:00:31) 
- `newestActivityMs` = ~1788681599439 (03:59:59)
- Check: Is `newestActivityMs < now - 120000`?
- 03:59:59 < 03:58:31? **NO**
- Therefore: backlog is NOT draining → proceed with boundary detection

The check thought the system was caught up because:
1. Activity was only 32 seconds behind "now" (well within the 2-minute threshold)
2. Flushes were arriving regularly

But it didn't know that the NEXT flush (arriving 5 seconds later) would contain a segment that changes the boundary decision!

### The Race Condition

This is a **classic race condition** between:
1. When the extension observes activity (03:59:59 - 04:00:05)
2. When the extension buffers and sends the flush (04:00:36)
3. When other flushes arrive and trigger boundary checks (04:00:31)

The backlog draining check works well for catching backlogs of OLD activity. But it can't detect that activity from 30 seconds ago is still in transit.

## The Fix

The issue is that `ingestCaughtUpMs = 120 seconds` is measuring the wrong thing. It's asking "is activity recent?" when it should be asking "could there be in-flight flushes for times around the boundary?"

### Option 1: Increase the Threshold

Increase `ingestCaughtUpMs` from 120 seconds to something larger (e.g., 300 seconds or 5 minutes).

**Pros:**
- Simple one-line change
- More conservative - less likely to freeze prematurely

**Cons:**
- Days won't freeze for 5 minutes after activity stops
- Doesn't eliminate the race, just makes it less likely

### Option 2: Never Freeze Before Target + IdleThreshold

Add a guard: don't freeze a day until "now" is at least `target + idleThreshold` (e.g., 4:00 + 90 minutes = 5:30).

**Pros:**
- Eliminates the race for the common case (activity near the target hour)
- Conceptually cleaner - the sliding boundary can't be decided until the slide window has elapsed

**Cons:**
- Days with no activity at target still wait unnecessarily
- Adds complexity

### Option 3: Two-Phase Freeze (RECOMMENDED)

Change the model:
1. **Tentative freeze**: Mark a boundary as "tentative" when first detected
2. **Confirmed freeze**: Only finalize it after `ingestCaughtUpMs` with no new crossing segments

**Pros:**
- Fixes the root cause
- Allows fast freezing when safe, conservative when risky
- Can recover from wrong tentative decisions

**Cons:**
- Requires schema/state changes
- More complex

### Option 4: Stricter Backlog Check

Add a check: if activity exists within `idleThreshold` of the target hour, consider the backlog draining until `target + idleThreshold` has passed.

```swift
if let lastActivity = newestActivityMs {
    let target = nextOccurrence(strictlyAfter: dayStart, hour: targetHour)
    if abs(lastActivity - target.epochMillis) < Int(idleThreshold * 1000) {
        // Activity near the boundary - wait for the full slide window
        if now < target + idleThreshold { 
            return start  // Keep day open
        }
    }
}
```

**Pros:**
- Surgical fix for exactly this case
- Doesn't delay freezing for days with no boundary activity

**Cons:**
- More complex logic
- Still has a race if multiple segments arrive out of order

## Recommended Solution

**Option 4 (Stricter Backlog Check) combined with increasing the threshold slightly.**

This gives defense in depth:
1. Special handling for activity near the boundary (prevents the 4 AM case)
2. Increased general threshold (prevents other edge cases)

### Implementation

```swift
private func backlogIsDraining(now: Date, dayStart: Date, targetHour: Int) throws -> Bool {
    var lastFlushMs = 0
    try database.query("SELECT COALESCE(MAX(received_at_ms), 0) FROM flushes") { row in lastFlushMs = row.int(0) }
    guard lastFlushMs >= now.epochMillis - Self.ingestActiveWindowMs else { return false }
    
    var newestActivityMs = 0
    try database.query("SELECT COALESCE(MAX(wall_end_ms), 0) FROM segments") { row in newestActivityMs = row.int(0) }
    try database.query("SELECT COALESCE(MAX(t_ms), 0) FROM raw_events") { row in newestActivityMs = max(newestActivityMs, row.int(0)) }
    
    // Standard check: backlog of old activity
    if newestActivityMs < now.epochMillis - Self.ingestCaughtUpMs {
        return true
    }
    
    // Special case: activity near the target hour might still be in flight
    let target = DayBoundary.nextOccurrence(strictlyAfter: dayStart, hour: targetHour, calendar: .current)
    let boundaryWindow = DayBoundary.idleThreshold * 1000  // 90 minutes in ms
    
    if newestActivityMs > target.epochMillis - boundaryWindow && 
       newestActivityMs < target.epochMillis + boundaryWindow {
        // Don't freeze until the full slide window after target has elapsed
        return now < target.addingTimeInterval(DayBoundary.idleThreshold)
    }
    
    return false
}
```

Also increase `ingestCaughtUpMs` from 120 seconds to 180 seconds (3 minutes) for additional safety.
