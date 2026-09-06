# Test the Fix RIGHT NOW (No Waiting!)

You're right - we can simulate this immediately! Here are **two ways** to test it within the next hour:

## Option 1: Real Activity Test (20-30 minutes)

Test with actual browser activity:

```bash
# 1. Set up the simulation (sets target hour to next hour)
node tools/simulate-boundary-crossing.js

# 2. Open ANY video in your browser
#    Keep it playing until AFTER the next hour mark
#    (e.g., if it's 10:45, keep playing until 11:01)

# 3. Check results
node tools/simulate-boundary-crossing.js --check
```

**What it does:**
- Changes your target hour to the next hour (e.g., 11:00)
- You create activity that crosses that boundary
- Script checks if day slides or freezes
- ✅ Tests the ACTUAL fix code, not a mock

**Expected result with fix:**
- Day stays open past the boundary
- Day slides to [last activity] + 90 minutes

**Bug result without fix:**
- Day freezes at exactly the target hour
- Activity after target goes to new day

## Option 2: Inject Test Data (Instant, but less reliable)

Quick test with fake segments:

```bash
# 1. Inject test data that crosses the next hour
node tools/simulate-boundary-crossing.js --inject

# 2. Wait until after that hour

# 3. Check results
node tools/simulate-boundary-crossing.js --check
```

**⚠️  WARNING**: This modifies your database with fake test data.

## What The Scripts Do

### Setup (`node tools/simulate-boundary-crossing.js`)
1. Gets current time (e.g., 10:45)
2. Calculates next hour (e.g., 11:00)
3. Sets target hour in `day_settings` table to 11
4. Shows you what to do next

### Check (`--check`)
1. Queries database for activity crossing the boundary
2. Checks if day froze at target or slid
3. Reports results:
   - ❌ "Day froze at exactly 11:00" = BUG
   - ✅ "Day slid by 90 minutes" = FIX WORKS

### Inject (`--inject`)
1. Creates fake segments crossing the boundary
2. Lets you test without browser activity
3. Less reliable because it's not real data flow

## Example Session

```bash
$ node tools/simulate-boundary-crossing.js
=== Day Boundary Crossing Simulation ===

Current time: 10:45:23
Next hour: 11:00 (in 15 minutes)

Step 1: Setting target hour...
  Current target hour: 4:00
  Setting to: 11:00
  ✅ Target hour updated

Step 2: Checking current open day...
  Current day started: 09/06/26 04:00:01

Step 3: Creating test activity...
  To properly test, you need to:
  1. Open a video in your browser NOW
  2. Keep it playing until AFTER 11:00
  3. Stop it after 11:01 (just 1 minute past)
  4. Run this script again with --check to see results

# [Wait 16 minutes, watching a video]

$ node tools/simulate-boundary-crossing.js --check
=== Checking Simulation Results ===

Current time: 11:02:15
Target hour: 11:00

Open day started: 09/06/26 04:00:01

✅ Found 1 segment(s) crossing the boundary:
   10:58:30 → 11:01:45 (watched)

📊 Day has been FROZEN:
   Date: 2026-09-06
   Start: 09/06/26 04:00:01
   End: 09/06/26 12:31:45

✅ SUCCESS: Day slid by 91 minutes!
   Expected: ~90 minutes (if fix is working)
   Actual: 91 minutes
   ✅ This matches the expected slide behavior!
```

## Why This Works

This tests the **actual fix code** in `EventStore.swift`:

1. When you change the target hour to 11:00, the app uses that
2. When you create activity crossing 11:00, it triggers the boundary logic
3. The fix detects activity within 90 min of target
4. It waits before freezing
5. The check script verifies the behavior

This is a **real simulation**, not a mock!

## After Testing

Reset your target hour back to 4:

```bash
# Open the app's menu bar
# Click "Day Boundary..."
# Change back to 4
```

Or via database:
```bash
sqlite3 ~/Library/Application\ Support/WatchLogs/watchlogs.sqlite \
  "UPDATE day_settings SET target_hour = 4 WHERE id = 1"
```

## Summary

- ⏰ **No waiting until tomorrow**
- 🎯 **Tests the actual fix code**
- 📊 **Clear pass/fail results**
- ⚡ **Results in 20-30 minutes** (or instant with --inject)

Run `node tools/simulate-boundary-crossing.js` now to start!
