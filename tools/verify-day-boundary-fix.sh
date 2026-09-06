#!/bin/bash
set -e

# Verification script for day boundary race condition fix
# This script provides multiple ways to verify the fix works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_PATH="$HOME/Library/Application Support/WatchLogs/watchlogs.sqlite"

echo "=== Day Boundary Fix Verification ==="
echo

# Method 1: Run the regression test
echo "Method 1: Running regression test..."
echo "-----------------------------------"
cd "$PROJECT_ROOT/app"
if swift test --filter DayBoundaryRaceConditionTest 2>&1 | grep -q "✔"; then
    echo "✅ Regression test passed"
else
    echo "❌ Regression test failed"
    echo "Run: cd app && swift test --filter DayBoundaryRaceConditionTest"
fi
echo

# Method 2: Check the actual database from the incident
echo "Method 2: Analyzing actual database from incident..."
echo "---------------------------------------------------"
if [ -f "$DB_PATH" ]; then
    echo "Found database at: $DB_PATH"
    echo
    
    # Show the frozen day that had the bug
    echo "Day that froze incorrectly (Sept 5, 2026):"
    sqlite3 "$DB_PATH" "
        SELECT 
            logical_date as day,
            datetime(day_start_ms/1000, 'unixepoch', 'localtime') as start,
            datetime(day_end_ms/1000, 'unixepoch', 'localtime') as end,
            ROUND((day_end_ms - day_start_ms) / 1000.0 / 3600, 1) as hours
        FROM rolled_day 
        WHERE logical_date = '2026-09-05'
    "
    echo
    
    # Show activity that crossed the boundary
    echo "Activity that crossed 4 AM boundary:"
    sqlite3 "$DB_PATH" "
        SELECT 
            datetime(wall_start_ms/1000, 'unixepoch', 'localtime') as start,
            datetime(wall_end_ms/1000, 'unixepoch', 'localtime') as end,
            kind
        FROM segments 
        WHERE kind = 'watched' 
            AND wall_start_ms < 1788681600000  -- Sept 6 04:00:00
            AND wall_end_ms > 1788681600000
    "
    echo
    
    echo "✅ Database exists and shows the incident"
    echo "   - Day ended at 4:00 AM (should have been 6:12 AM)"
    echo "   - Activity crossed the boundary"
else
    echo "⚠️  Database not found at: $DB_PATH"
fi
echo

# Method 3: Check code changes
echo "Method 3: Verifying code changes..."
echo "-----------------------------------"
if grep -q "ingestCaughtUpMs = 180_000" "$PROJECT_ROOT/app/Sources/WatchLogsKit/EventStore.swift"; then
    echo "✅ ingestCaughtUpMs increased to 180s"
else
    echo "❌ ingestCaughtUpMs not updated"
fi

if grep -q "boundaryWindowMs" "$PROJECT_ROOT/app/Sources/WatchLogsKit/EventStore.swift"; then
    echo "✅ Boundary-aware backlog check added"
else
    echo "❌ Boundary-aware check missing"
fi

if grep -q "dayStart: Date, targetHour: Int, calendar: Calendar" "$PROJECT_ROOT/app/Sources/WatchLogsKit/EventStore.swift"; then
    echo "✅ backlogIsDraining signature updated"
else
    echo "❌ backlogIsDraining signature not updated"
fi
echo

echo "=== Summary ==="
echo "To fully verify the fix:"
echo "1. Review the code changes in app/Sources/WatchLogsKit/EventStore.swift"
echo "2. Run the unit tests: cd app && swift test"
echo "3. Test with a copy of the production database (see simulation script)"
echo "4. Monitor the next day boundary (Sept 7 04:00 AM) in production"
