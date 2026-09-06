// Day boundary diagnostics — generic analyzer.
//
// Given a date and target hour, this inspects the DB around that boundary and
// explains what likely happened: when the first post-target flush arrived,
// whether there were watched segments crossing the target, what got frozen, and
// when the day would be expected to end if activity was near the boundary.

const DEFAULT_TARGET_HOUR = 4;
const DEFAULT_WINDOW_MINUTES = 90;

export function analyzeDayBoundary(db, options = {}) {
  const date = parseIsoDate(options.date) ?? localIsoDate(new Date());
  const targetHour = parseHour(options.targetHour) ?? DEFAULT_TARGET_HOUR;
  const boundaryWindowMs = (parseInt(options.windowMinutes ?? DEFAULT_WINDOW_MINUTES, 10) || DEFAULT_WINDOW_MINUTES) * 60 * 1000;

  const targetMs = localDateAtHourMs(date, targetHour);
  const previousLogicalDate = shiftIsoDate(date, -1);

  const firstFlush = firstFlushAtOrAfter(db, targetMs);
  const crossing = crossingSegmentAtTarget(db, targetMs);
  const crossingFirstFlush = crossing ? firstFlushForView(db, crossing.view_id) : null;

  return {
    config: {
      date,
      targetHour,
      boundaryWindowMinutes: Math.round(boundaryWindowMs / 60000),
      target: formatTimestamp(targetMs),
      targetMs,
      logicalDateExpected: previousLogicalDate,
    },
    summary: summarize(firstFlush, crossingFirstFlush),
    timeline: buildTimeline(db, { targetMs, firstFlush, crossing, crossingFirstFlush }),
    crossingSegment: crossing
      ? {
          viewId: crossing.view_id,
          start: formatTimestamp(crossing.wall_start_ms),
          end: formatTimestamp(crossing.wall_end_ms),
          firstFlush: crossingFirstFlush ? formatTimestamp(crossingFirstFlush.received_at_ms) : null,
          arrivedBeforeFirstPostTargetFlush:
            !!firstFlush && !!crossingFirstFlush && crossingFirstFlush.received_at_ms <= firstFlush.received_at_ms,
        }
      : null,
    newestActivity: newestActivityBefore(db, firstFlush?.received_at_ms ?? targetMs + 2 * 60_000, targetMs, boundaryWindowMs),
    fixAnalysis: analyzeFixBehavior(db, targetMs, boundaryWindowMs),
    actualResult: actualFrozenDay(db, previousLogicalDate),
    expectedResult: expectedBoundary(db, targetMs, boundaryWindowMs),
    segmentsAtCriticalMoment: watchedSegmentsNear(db, targetMs, firstFlush?.received_at_ms ?? targetMs + 2 * 60_000, boundaryWindowMs),
  };
}

function summarize(firstFlush, crossingFirstFlush) {
  if (!firstFlush) return 'No flush was found at or after the target hour.';
  if (!crossingFirstFlush) {
    return 'A post-target flush exists, but no crossing segment flush was found for this window.';
  }
  if (crossingFirstFlush.received_at_ms > firstFlush.received_at_ms) {
    return 'Possible race: boundary-triggering flush arrived before the crossing-segment flush.';
  }
  return 'No race signal from flush ordering: crossing-segment flush arrived before or with the first post-target flush.';
}

function buildTimeline(db, { targetMs, firstFlush, crossing, crossingFirstFlush }) {
  const events = [
    { timestamp: targetMs, time: formatTimestamp(targetMs), event: 'Target hour boundary' },
  ];

  if (crossing) {
    events.push({
      timestamp: crossing.wall_start_ms,
      time: formatTimestamp(crossing.wall_start_ms),
      event: 'Watched segment starts (crosses boundary)',
    });
    events.push({
      timestamp: crossing.wall_end_ms,
      time: formatTimestamp(crossing.wall_end_ms),
      event: 'Watched segment ends',
    });
  }

  if (firstFlush) {
    events.push({
      timestamp: firstFlush.received_at_ms,
      time: formatTimestamp(firstFlush.received_at_ms),
      event: 'First flush at/after target (boundary check candidate)',
      flushId: firstFlush.flush_id,
    });
  }

  if (crossingFirstFlush) {
    events.push({
      timestamp: crossingFirstFlush.received_at_ms,
      time: formatTimestamp(crossingFirstFlush.received_at_ms),
      event: 'First flush mentioning the crossing view',
      flushId: crossingFirstFlush.flush_id,
    });
  }

  const around = db
    .prepare(
      `
      SELECT received_at_ms, flush_id
      FROM flushes
      WHERE received_at_ms >= ? AND received_at_ms <= ?
      ORDER BY received_at_ms
      LIMIT 30
    `
    )
    .all(targetMs - 60_000, targetMs + 180_000);

  for (const flush of around) {
    events.push({
      timestamp: flush.received_at_ms,
      time: formatTimestamp(flush.received_at_ms),
      event: 'Flush arrives',
      flushId: flush.flush_id,
    });
  }

  const seen = new Set();
  return events
    .sort((a, b) => a.timestamp - b.timestamp)
    .filter((e) => {
      const key = `${e.timestamp}:${e.event}:${e.flushId ?? ''}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function watchedSegmentsNear(db, targetMs, beforeMs, windowMs) {
  const rows = db
    .prepare(
      `
      SELECT wall_start_ms, wall_end_ms, view_id,
             CASE WHEN wall_start_ms < ? AND wall_end_ms > ? THEN 1 ELSE 0 END AS crosses_boundary
      FROM segments
      WHERE kind = 'watched'
        AND wall_end_ms > ? - ?
        AND wall_end_ms < ?
      ORDER BY wall_start_ms DESC
      LIMIT 30
    `
    )
    .all(targetMs, targetMs, targetMs, windowMs, beforeMs);

  return rows.map((seg) => ({
    start: formatTimestamp(seg.wall_start_ms),
    end: formatTimestamp(seg.wall_end_ms),
    viewId: seg.view_id,
    crossesBoundary: seg.crosses_boundary === 1,
  }));
}

function crossingSegmentAtTarget(db, targetMs) {
  return (
    db
      .prepare(
        `
      SELECT wall_start_ms, wall_end_ms, view_id
      FROM segments
      WHERE kind = 'watched'
        AND wall_start_ms < ?
        AND wall_end_ms > ?
      ORDER BY wall_start_ms DESC
      LIMIT 1
    `
      )
      .get(targetMs, targetMs) ?? null
  );
}

function firstFlushAtOrAfter(db, targetMs) {
  return (
    db
      .prepare('SELECT received_at_ms, flush_id FROM flushes WHERE received_at_ms >= ? ORDER BY received_at_ms LIMIT 1')
      .get(targetMs) ?? null
  );
}

function firstFlushForView(db, viewId) {
  return (
    db
      .prepare(
        `
      SELECT received_at_ms, flush_id
      FROM flushes
      WHERE ack_json LIKE ?
      ORDER BY received_at_ms
      LIMIT 1
    `
      )
      .get(`%${viewId}%`) ?? null
  );
}

function newestActivityBefore(db, beforeMs, targetMs, windowMs) {
  const result =
    db
      .prepare('SELECT MAX(wall_end_ms) AS newest_ms FROM segments WHERE wall_end_ms < ?')
      .get(beforeMs) ?? null;
  if (!result?.newest_ms) return null;

  const diffFromTarget = result.newest_ms - targetMs;
  return {
    timestamp: formatTimestamp(result.newest_ms),
    timestampMs: result.newest_ms,
    minutesFromTarget: Math.round((diffFromTarget / 60000) * 10) / 10,
    withinBoundaryWindow: Math.abs(diffFromTarget) < windowMs,
  };
}

function analyzeFixBehavior(db, targetMs, windowMs) {
  const newest = newestActivityBefore(db, targetMs + 2 * 60_000, targetMs, windowMs);
  if (!newest) return null;
  const waitUntil = targetMs + windowMs;
  const withinWindow = newest.withinBoundaryWindow;
  return {
    activityWithinWindow: withinWindow,
    newestActivity: newest.timestamp,
    targetHour: formatTimestamp(targetMs),
    windowEnd: formatTimestamp(waitUntil),
    fixBehavior: withinWindow
      ? `Activity near boundary: wait until ${formatTimestamp(waitUntil)} before freezing.`
      : 'No near-boundary activity: freeze can proceed at normal boundary checks.',
    prevented: withinWindow,
  };
}

function actualFrozenDay(db, logicalDate) {
  const day =
    db
      .prepare(
        `
      SELECT logical_date, day_start_ms, day_end_ms
      FROM rolled_day
      WHERE logical_date = ?
    `
      )
      .get(logicalDate) ?? null;
  if (!day) return null;

  return {
    date: day.logical_date,
    start: formatTimestamp(day.day_start_ms),
    end: formatTimestamp(day.day_end_ms),
    durationHours: Math.round(((day.day_end_ms - day.day_start_ms) / 3600000) * 10) / 10,
  };
}

function expectedBoundary(db, targetMs, windowMs) {
  const result =
    db
      .prepare(
        `
      SELECT MAX(wall_end_ms) AS last_activity_ms
      FROM segments
      WHERE kind = 'watched'
        AND wall_start_ms >= ? - 86400000
        AND wall_start_ms < ? + 21600000
    `
      )
      .get(targetMs, targetMs) ?? null;

  if (!result?.last_activity_ms) return null;
  const shouldEnd = result.last_activity_ms + windowMs;
  return {
    lastActivity: formatTimestamp(result.last_activity_ms),
    shouldEndAt: formatTimestamp(shouldEnd),
    slidMinutes: Math.round(windowMs / 60000),
  };
}

function parseIsoDate(text) {
  if (!text || typeof text !== 'string') return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
  return text;
}

function parseHour(value) {
  const n = parseInt(value, 10);
  return Number.isInteger(n) && n >= 0 && n <= 23 ? n : null;
}

function localDateAtHourMs(isoDate, hour) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(y, m - 1, d, hour, 0, 0, 0).getTime();
}

function localIsoDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function shiftIsoDate(isoDate, days) {
  const [y, m, d] = isoDate.split('-').map(Number);
  const date = new Date(y, m - 1, d, 12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return localIsoDate(date);
}

function formatTimestamp(ms) {
  if (!ms) return null;
  return new Date(ms).toLocaleString();
}
