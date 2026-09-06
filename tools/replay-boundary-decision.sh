#!/bin/bash
set -e

# Replays the boundary decision from the incident using the actual database
# This shows what WOULD have happened with the fix in place

DB_PATH="$HOME/Library/Application Support/WatchLogs/watchlogs.sqlite"

echo "=== Replaying Day Boundary Decision (Sept 6, 2026) ==="
echo

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    exit 1
fi

echo "Database: $DB_PATH"
echo

# The critical moments
TARGET_HOUR="1788681600000"  # Sept 6, 04:00:00
FIRST_FLUSH="1788681631618"  # Sept 6, 04:00:31 (when race happened)
LATE_FLUSH="1788681636621"   # Sept 6, 04:00:36 (crossing segment arrived)

echo "Timeline from incident:"
echo "----------------------"
echo "Target hour:    Sept 6, 04:00:00"
echo "First flush:    Sept 6, 04:00:31 (triggered boundary check)"
echo "Late flush:     Sept 6, 04:00:36 (crossing segment arrived)"
echo

# Show what segments existed at the critical moment (04:00:31)
echo "Segments in database at 04:00:31 (when boundary check ran):"
echo "-----------------------------------------------------------"
sqlite3 "$DB_PATH" <<SQL
SELECT 
    datetime(wall_start_ms/1000, 'unixepoch', 'localtime') as start,
    datetime(wall_end_ms/1000, 'unixepoch', 'localtime') as end,
    CASE 
        WHEN wall_start_ms < $TARGET_HOUR AND wall_end_ms > $TARGET_HOUR 
        THEN '← CROSSES 4 AM'
        ELSE ''
    END as crosses
FROM segments 
WHERE kind = 'watched'
    AND wall_end_ms > $TARGET_HOUR - 5400000  -- 90 min before target
    AND wall_end_ms < $FIRST_FLUSH             -- only segments that existed at 04:00:31
ORDER BY wall_start_ms DESC
LIMIT 20;
SQL
echo

# Check if crossing segment existed
CROSSING_EXISTS=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) 
    FROM segments 
    WHERE kind = 'watched'
        AND wall_start_ms < $TARGET_HOUR 
        AND wall_end_ms > $TARGET_HOUR
        AND wall_end_ms < $FIRST_FLUSH
")

echo "Critical Analysis:"
echo "------------------"
if [ "$CROSSING_EXISTS" -eq "0" ]; then
    echo "❌ NO crossing segment in database at 04:00:31"
    echo "   → Without fix: Day freezes at 04:00:00"
    echo "   → With fix: Backlog check detects activity near boundary, waits"
else
    echo "✅ Crossing segment WAS in database at 04:00:31"
    echo "   → Boundary logic would correctly slide the day"
fi
echo

# Show the newest activity at the critical moment
echo "Newest activity at 04:00:31:"
echo "----------------------------"
sqlite3 "$DB_PATH" <<SQL
SELECT 
    datetime(MAX(wall_end_ms)/1000, 'unixepoch', 'localtime') as newest_activity,
    MAX(wall_end_ms) as newest_activity_ms,
    ROUND((MAX(wall_end_ms) - $TARGET_HOUR) / 1000.0 / 60, 1) as minutes_from_target
FROM segments 
WHERE wall_end_ms < $FIRST_FLUSH;
SQL
echo

# Show what the fix does
echo "How the fix works:"
echo "------------------"
NEWEST_ACTIVITY=$(sqlite3 "$DB_PATH" "SELECT MAX(wall_end_ms) FROM segments WHERE wall_end_ms < $FIRST_FLUSH")
BOUNDARY_WINDOW=5400000  # 90 minutes in milliseconds

if [ -n "$NEWEST_ACTIVITY" ]; then
    DIFF_FROM_TARGET=$((NEWEST_ACTIVITY - TARGET_HOUR))
    
    if [ $DIFF_FROM_TARGET -gt -$BOUNDARY_WINDOW ] && [ $DIFF_FROM_TARGET -lt $BOUNDARY_WINDOW ]; then
        echo "✅ Activity within 90 minutes of target hour"
        echo "   Newest: $(sqlite3 "$DB_PATH" "SELECT datetime($NEWEST_ACTIVITY/1000, 'unixepoch', 'localtime')")"
        echo "   Target: Sept 6, 04:00:00"
        echo "   → Fix: Wait until 05:30:00 before deciding boundary"
        echo "   → This gives late flushes time to arrive"
    else
        echo "Activity NOT near boundary, would freeze normally"
    fi
fi
echo

# Show the actual frozen day
echo "Actual result (with bug):"
echo "-------------------------"
sqlite3 "$DB_PATH" <<SQL
SELECT 
    'Day: ' || logical_date,
    'Start: ' || datetime(day_start_ms/1000, 'unixepoch', 'localtime'),
    'End: ' || datetime(day_end_ms/1000, 'unixepoch', 'localtime'),
    'Duration: ' || ROUND((day_end_ms - day_start_ms) / 1000.0 / 3600, 1) || ' hours'
FROM rolled_day 
WHERE logical_date = '2026-09-05';
SQL
echo

# Show what SHOULD have happened
echo "What should have happened (with fix):"
echo "--------------------------------------"
LAST_ACTIVITY=$(sqlite3 "$DB_PATH" "SELECT MAX(wall_end_ms) FROM segments WHERE wall_start_ms >= $TARGET_HOUR - 86400000 AND wall_start_ms < $TARGET_HOUR + 21600000")
if [ -n "$LAST_ACTIVITY" ]; then
    SHOULD_END=$((LAST_ACTIVITY + 5400000))  # 90 min after last activity
    echo "Last activity: $(sqlite3 "$DB_PATH" "SELECT datetime($LAST_ACTIVITY/1000, 'unixepoch', 'localtime')")"
    echo "Day should end: $(sqlite3 "$DB_PATH" "SELECT datetime($SHOULD_END/1000, 'unixepoch', 'localtime')")"
fi
echo

echo "=== Verification ==="
echo "The fix ensures that when activity exists near the boundary,"
echo "the system waits for the full slide window before deciding."
echo
echo "Next step: Monitor the next boundary (Sept 7, 04:00 AM) to"
echo "verify the fix works in production."
