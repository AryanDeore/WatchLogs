// Day boundary diagnostics for the 2026-09-06 race condition incident.
// This analyzes the database to show what happened at the critical moment
// and verifies that the fix would have prevented the issue.

const TARGET_HOUR_MS = 1788681600000; // Sept 6, 04:00:00
const FIRST_FLUSH_MS = 1788681631618; // Sept 6, 04:00:31 (when race happened)
const LATE_FLUSH_MS = 1788681636621; // Sept 6, 04:00:36 (crossing segment flush)
const BOUNDARY_WINDOW_MS = 90 * 60 * 1000; // 90 minutes

export function analyzeDayBoundary(db) {
  const analysis = {
    incident: getIncidentSummary(db),
    timeline: getTimeline(db),
    segments: getSegmentsAtCriticalMoment(db),
    crossingSegment: getCrossingSegment(db),
    newestActivity: getNewestActivity(db),
    fixAnalysis: analyzeHowFixWorks(db),
    actualResult: getActualFrozenDay(db),
    expectedResult: getExpectedResult(db),
  };

  return analysis;
}

function getIncidentSummary(db) {
  return {
    date: '2026-09-06',
    targetHour: formatTimestamp(TARGET_HOUR_MS),
    firstFlush: formatTimestamp(FIRST_FLUSH_MS),
    lateFlush: formatTimestamp(LATE_FLUSH_MS),
    description: 'Day boundary froze at 04:00:00 instead of sliding to 06:12:03',
  };
}

function getTimeline(db) {
  const events = [];

  // Key activity moments
  const crossingSegQuery = db.prepare(`
    SELECT wall_start_ms, wall_end_ms
    FROM segments
    WHERE kind = 'watched'
      AND wall_start_ms < ?
      AND wall_end_ms > ?
    LIMIT 1
  `);
  const crossing = crossingSegQuery.get(TARGET_HOUR_MS, TARGET_HOUR_MS);

  if (crossing) {
    events.push({
      time: formatTimestamp(crossing.wall_start_ms),
      timestamp: crossing.wall_start_ms,
      event: 'Activity starts (crosses 4 AM boundary)',
      type: 'activity',
    });
    events.push({
      time: formatTimestamp(crossing.wall_end_ms),
      timestamp: crossing.wall_end_ms,
      event: 'Activity ends',
      type: 'activity',
    });
  }

  // Flushes around the critical time
  const flushQuery = db.prepare(`
    SELECT received_at_ms, flush_id
    FROM flushes
    WHERE received_at_ms >= ?
      AND received_at_ms <= ?
    ORDER BY received_at_ms
    LIMIT 20
  `);
  const flushes = flushQuery.all(TARGET_HOUR_MS - 60000, TARGET_HOUR_MS + 120000);

  flushes.forEach((flush) => {
    let description = 'Flush arrives';
    if (flush.received_at_ms === FIRST_FLUSH_MS) {
      description = '⚠️ Flush triggers boundary check (race condition moment)';
    } else if (flush.received_at_ms === LATE_FLUSH_MS) {
      description = 'Crossing segment flush arrives';
    }
    events.push({
      time: formatTimestamp(flush.received_at_ms),
      timestamp: flush.received_at_ms,
      event: description,
      type: 'flush',
      flushId: flush.flush_id,
    });
  });

  return events.sort((a, b) => a.timestamp - b.timestamp);
}

function getSegmentsAtCriticalMoment(db) {
  const query = db.prepare(`
    SELECT 
      wall_start_ms,
      wall_end_ms,
      view_id,
      CASE 
        WHEN wall_start_ms < ? AND wall_end_ms > ?
        THEN 1
        ELSE 0
      END as crosses_boundary
    FROM segments
    WHERE kind = 'watched'
      AND wall_end_ms > ? - ?
      AND wall_end_ms < ?
    ORDER BY wall_start_ms DESC
    LIMIT 30
  `);

  const segments = query.all(
    TARGET_HOUR_MS,
    TARGET_HOUR_MS,
    TARGET_HOUR_MS,
    BOUNDARY_WINDOW_MS,
    FIRST_FLUSH_MS
  );

  return segments.map((seg) => ({
    start: formatTimestamp(seg.wall_start_ms),
    end: formatTimestamp(seg.wall_end_ms),
    viewId: seg.view_id,
    crossesBoundary: seg.crosses_boundary === 1,
  }));
}

function getCrossingSegment(db) {
  const query = db.prepare(`
    SELECT 
      wall_start_ms,
      wall_end_ms,
      view_id
    FROM segments
    WHERE kind = 'watched'
      AND wall_start_ms < ?
      AND wall_end_ms > ?
    LIMIT 1
  `);

  const seg = query.get(TARGET_HOUR_MS, TARGET_HOUR_MS);
  if (!seg) return null;

  // Check when this view's flushes arrived
  const flushQuery = db.prepare(`
    SELECT received_at_ms, flush_id
    FROM flushes
    WHERE ack_json LIKE ?
    ORDER BY received_at_ms
    LIMIT 5
  `);

  const flushes = flushQuery.all(`%${seg.view_id}%`);

  return {
    start: formatTimestamp(seg.wall_start_ms),
    end: formatTimestamp(seg.wall_end_ms),
    viewId: seg.view_id,
    existedAtCriticalMoment: seg.wall_end_ms < FIRST_FLUSH_MS,
    flushes: flushes.map((f) => ({
      time: formatTimestamp(f.received_at_ms),
      timestamp: f.received_at_ms,
      flushId: f.flush_id,
      beforeCriticalMoment: f.received_at_ms < FIRST_FLUSH_MS,
    })),
  };
}

function getNewestActivity(db) {
  const query = db.prepare(`
    SELECT MAX(wall_end_ms) as newest_ms
    FROM segments
    WHERE wall_end_ms < ?
  `);

  const result = query.get(FIRST_FLUSH_MS);
  if (!result || !result.newest_ms) return null;

  const diffFromTarget = result.newest_ms - TARGET_HOUR_MS;
  const minutesFromTarget = diffFromTarget / 60000;

  return {
    timestamp: formatTimestamp(result.newest_ms),
    timestampMs: result.newest_ms,
    minutesFromTarget: Math.round(minutesFromTarget * 10) / 10,
    withinBoundaryWindow: Math.abs(diffFromTarget) < BOUNDARY_WINDOW_MS,
  };
}

function analyzeHowFixWorks(db) {
  const newest = getNewestActivity(db);
  if (!newest) return null;

  const withinWindow = newest.withinBoundaryWindow;
  const waitUntil = TARGET_HOUR_MS + BOUNDARY_WINDOW_MS; // 05:30:00

  return {
    activityWithinWindow: withinWindow,
    newestActivity: newest.timestamp,
    targetHour: formatTimestamp(TARGET_HOUR_MS),
    windowEnd: formatTimestamp(waitUntil),
    fixBehavior: withinWindow
      ? `✅ Fix detects activity near boundary, waits until ${formatTimestamp(waitUntil)}`
      : 'Activity not near boundary, would freeze normally',
    prevented: withinWindow,
  };
}

function getActualFrozenDay(db) {
  const query = db.prepare(`
    SELECT 
      logical_date,
      day_start_ms,
      day_end_ms
    FROM rolled_day
    WHERE logical_date = '2026-09-05'
  `);

  const day = query.get();
  if (!day) return null;

  const durationHours = (day.day_end_ms - day.day_start_ms) / (1000 * 3600);

  return {
    date: day.logical_date,
    start: formatTimestamp(day.day_start_ms),
    end: formatTimestamp(day.day_end_ms),
    durationHours: Math.round(durationHours * 10) / 10,
    frozeAtTarget: day.day_end_ms === TARGET_HOUR_MS,
  };
}

function getExpectedResult(db) {
  // Find the last activity in the day
  const query = db.prepare(`
    SELECT MAX(wall_end_ms) as last_activity_ms
    FROM segments
    WHERE kind = 'watched'
      AND wall_start_ms >= ? - 86400000
      AND wall_start_ms < ? + 21600000
  `);

  const result = query.get(TARGET_HOUR_MS, TARGET_HOUR_MS);
  if (!result || !result.last_activity_ms) return null;

  const shouldEnd = result.last_activity_ms + BOUNDARY_WINDOW_MS;

  return {
    lastActivity: formatTimestamp(result.last_activity_ms),
    shouldEndAt: formatTimestamp(shouldEnd),
    slidMinutes: 90,
  };
}

function formatTimestamp(ms) {
  if (!ms) return null;
  const date = new Date(ms);
  return date.toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles', // Adjust to your timezone
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
}
