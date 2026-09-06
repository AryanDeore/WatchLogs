#!/usr/bin/env node

/**
 * Replay one boundary decision from stored data and print a clear verdict.
 *
 * This does not wait for real time. It replays "what was known at the first
 * post-target flush" and checks whether the Sept-06 fix would defer freezing.
 *
 * Usage:
 *   node tools/replay-boundary-verdict.js
 *   node tools/replay-boundary-verdict.js --date=2026-09-06 --targetHour=4 --windowMinutes=90
 *
 * Defaults:
 *   date: yesterday (local)
 *   targetHour: day_settings.target_hour (or 4)
 *   windowMinutes: 90
 */

import { DatabaseSync } from 'node:sqlite';
import { homedir } from 'node:os';
import { join } from 'node:path';

const DB_PATH = process.env.WATCHLOGS_DB || join(homedir(), 'Library/Application Support/WatchLogs/watchlogs.sqlite');
const INGEST_CAUGHT_UP_MS = 180_000;

function args() {
  const out = {};
  for (const arg of process.argv.slice(2)) {
    if (!arg.startsWith('--')) continue;
    const [k, v = 'true'] = arg.slice(2).split('=', 2);
    out[k] = v;
  }
  return out;
}

function localIsoDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function shiftIsoDate(iso, days) {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d, 12, 0, 0, 0);
  dt.setDate(dt.getDate() + days);
  return localIsoDate(dt);
}

function atLocalHourMs(isoDate, hour) {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(y, m - 1, d, hour, 0, 0, 0).getTime();
}

function fmt(ms) {
  return ms == null ? '—' : new Date(ms).toLocaleString();
}

function parseHour(raw, fallback) {
  const n = Number(raw);
  return Number.isInteger(n) && n >= 0 && n <= 23 ? n : fallback;
}

function main() {
  const db = new DatabaseSync(DB_PATH, { readOnly: true });
  const a = args();

  const configuredHour = db.prepare('SELECT target_hour FROM day_settings WHERE id = 1').get()?.target_hour ?? 4;
  const date = /^\d{4}-\d{2}-\d{2}$/.test(a.date || '') ? a.date : shiftIsoDate(localIsoDate(new Date()), -1);
  const targetHour = parseHour(a.targetHour, configuredHour);
  const windowMinutes = Math.max(1, Number.parseInt(a.windowMinutes ?? '90', 10) || 90);
  const windowMs = windowMinutes * 60 * 1000;

  const targetMs = atLocalHourMs(date, targetHour);
  const logicalDate = shiftIsoDate(date, -1);

  const firstFlush = db
    .prepare('SELECT received_at_ms, flush_id FROM flushes WHERE received_at_ms >= ? ORDER BY received_at_ms LIMIT 1')
    .get(targetMs);

  console.log('=== Boundary Replay Verdict ===');
  console.log(`DB: ${DB_PATH}`);
  console.log(`Boundary date: ${date}`);
  console.log(`Target hour: ${targetHour}:00`);
  console.log(`Window: ${windowMinutes} min`);
  console.log(`Target instant: ${fmt(targetMs)}`);
  console.log('');

  if (!firstFlush) {
    console.log('VERDICT: INCONCLUSIVE');
    console.log('Reason: no flush at/after target hour in this DB window.');
    return;
  }

  const nowMs = firstFlush.received_at_ms;

  const newestSegmentMs = db
    .prepare('SELECT COALESCE(MAX(wall_end_ms), 0) AS n FROM segments WHERE wall_end_ms <= ?')
    .get(nowMs).n;
  const newestEventMs = db
    .prepare('SELECT COALESCE(MAX(t_ms), 0) AS n FROM raw_events WHERE t_ms <= ?')
    .get(nowMs).n;
  const newestActivityMs = Math.max(newestSegmentMs, newestEventMs);

  const withinBoundaryWindow = newestActivityMs > targetMs - windowMs && newestActivityMs < targetMs + windowMs;
  const backlogOldActivity = newestActivityMs < nowMs - INGEST_CAUGHT_UP_MS;

  const fixWouldDefer = withinBoundaryWindow && nowMs < targetMs + windowMs;
  const likelyOldBehaviorFreeze = !fixWouldDefer && !backlogOldActivity;

  const rolled = db
    .prepare('SELECT logical_date, day_start_ms, day_end_ms FROM rolled_day WHERE logical_date = ?')
    .get(logicalDate);

  console.log(`First post-target flush: ${fmt(nowMs)} (${firstFlush.flush_id})`);
  console.log(`Newest activity visible at that moment: ${fmt(newestActivityMs)}`);
  console.log(`Near boundary window? ${withinBoundaryWindow ? 'yes' : 'no'}`);
  console.log(`Looks like old backlog drain (activity >3m behind)? ${backlogOldActivity ? 'yes' : 'no'}`);
  console.log('');

  if (fixWouldDefer) {
    console.log('VERDICT: FIX WOULD WAIT/SLIDE ✅');
    console.log(`Why: activity was near target; decision should defer until ${fmt(targetMs + windowMs)}.`);
  } else if (likelyOldBehaviorFreeze) {
    console.log('VERDICT: WOULD ALLOW FREEZE AT/NEAR TARGET ⚠️');
    console.log('Why: no near-boundary activity signal at the first decision point.');
  } else {
    console.log('VERDICT: INCONCLUSIVE');
    console.log('Why: signals look like backlog drain/partial ingest rather than clean near-boundary case.');
  }

  console.log('');
  if (rolled) {
    const pinnedAtTarget = Math.abs(rolled.day_end_ms - targetMs) < 60_000;
    console.log(`Actual rolled_day[${rolled.logical_date}] end: ${fmt(rolled.day_end_ms)}`);
    console.log(`Pinned at target hour? ${pinnedAtTarget ? 'yes' : 'no'}`);
  } else {
    console.log(`Actual rolled_day[${logicalDate}]: not found`);
  }
}

main();
