# Why Your Day Ended at 4 AM Instead of Sliding

## TL;DR

Your day (Sept 5) was frozen at 4:00 AM instead of sliding to 6:12 AM because of a **race condition**: the app checked whether to freeze the day **before** the flush containing your 3:59-4:00 AM activity arrived from the browser extension.

## What Happened

1. **3:59:59 - 4:00:05 AM**: You were watching something that crossed the 4 AM boundary
2. **4:00:31 AM**: A flush arrived, the app checked if it should freeze yesterday's day
3. At that moment, the critical segment (3:59:59 → 4:00:05) **wasn't in the database yet**
4. The app saw no activity crossing 4 AM, so it froze the day at exactly 4:00 AM
5. **4:00:36 AM**: The flush with the crossing segment finally arrived - **but too late**, the day was already frozen

## Why the Safeguard Failed

There's a check called `backlogIsDraining` that's supposed to prevent exactly this problem. It prevents freezing when:
- Flushes are arriving regularly (last one within 15 seconds)
- BUT activity is way behind (more than 2 minutes old)

At 4:00:31:
- ✅ Flushes were arriving (last one was this one)
- ✅ Activity was recent (only 32 seconds old - the 3:59:59 segment)
- ❌ So it thought the system was caught up and safe to freeze

The check couldn't know that a flush with boundary-crossing activity was about to arrive 5 seconds later.

## How Much Got Mis-Filed

About **42 minutes** of watched time (4:00 AM to 4:42 AM) from Sept 5 is showing up in Sept 6 instead.

Looking at the database:
- Sept 5 day: `2026-09-05 04:00:00` → `2026-09-06 04:00:00` (should be → `2026-09-06 06:12:03`)
- Sept 6 day: `2026-09-06 04:00:00` → (still open)

## The Fix

I've analyzed several options in `day_boundary_bug_analysis.md`. The recommended fix is:

**Add special handling when activity is near the target hour**:
- If activity exists within 90 minutes of 4 AM (either side)
- Don't freeze the day until at least 90 minutes AFTER the target hour
- This gives all flushes time to arrive before making the boundary decision

Plus increase the general backlog threshold from 2 minutes to 3 minutes for additional safety.

This is a surgical fix that prevents the 4 AM case specifically without delaying unrelated freezes.

## Your Data

The data itself is fine - it's all recorded correctly, just filed under the wrong day label. The 42 minutes from 4:00-4:42 AM on Sept 6 should conceptually belong to Sept 5, but fixing historical data after the fact is risky (could double-count or lose time).

Going forward with the fix, this won't happen again.
