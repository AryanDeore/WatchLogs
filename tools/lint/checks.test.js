// Every check here is raw SQL against a schema that changes underneath it, so
// each one is pinned twice: it fires on the shape it was written for, and a
// clean database produces nothing at all.
//
// The second half matters more than the first. A check that cries wolf gets
// ignored, and an ignored check is worse than no check — it is a green light
// nobody reads.
//
//   node --test tools/lint/checks.test.js

import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { runChecks } from './checks.js';

const T0 = Date.UTC(2026, 8, 5, 21, 0, 0);

/** A database with the app's schema and nothing in it. */
function emptyDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE views (
      view_id TEXT PRIMARY KEY, service TEXT NOT NULL, content_format TEXT NOT NULL,
      embedded INTEGER NOT NULL, video_id TEXT NOT NULL, url TEXT NOT NULL,
      title TEXT, author TEXT, duration_sec REAL, metadata_source TEXT, adapter_id TEXT,
      tab_id INTEGER NOT NULL, started_at_ms INTEGER NOT NULL, open INTEGER NOT NULL,
      previous_view_id TEXT
    );
    CREATE TABLE segments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, view_id TEXT NOT NULL, kind TEXT NOT NULL,
      wall_start_ms INTEGER NOT NULL, wall_end_ms INTEGER NOT NULL,
      pos_start REAL, pos_end REAL, provisional INTEGER NOT NULL
    );
    CREATE TABLE raw_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, view_id TEXT NOT NULL, seq INTEGER NOT NULL,
      type TEXT NOT NULL, t_ms INTEGER NOT NULL, pos REAL, seek_from REAL, seek_to REAL,
      rate REAL, playing INTEGER, visible INTEGER, reason TEXT
    );
  `);
  return db;
}

function addView(db, { viewId, tabId = 1, title = 'A video', videoId = 'vid1', durationSec = 600, open = 0, format = 'standard', startedAt = T0 }) {
  db.prepare(
    `INSERT INTO views (view_id, service, content_format, embedded, video_id, url, title,
                        duration_sec, tab_id, started_at_ms, open)
     VALUES (?, 'youtube', ?, 0, ?, 'https://youtube.com/watch', ?, ?, ?, ?, ?)`
  ).run(viewId, format, videoId, title, durationSec, tabId, startedAt, open);
}

function addSegment(db, { viewId, kind = 'watched', from, to, posStart = 0, posEnd = null }) {
  db.prepare(
    `INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
     VALUES (?, ?, ?, ?, ?, ?, 0)`
  ).run(viewId, kind, from, to, posStart, posEnd ?? posStart + (to - from) / 1000);
}

function addEvent(db, { viewId, seq, type, at, pos = 0, playing = null, rate = null }) {
  db.prepare(
    `INSERT INTO raw_events (view_id, seq, type, t_ms, pos, playing, rate) VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(viewId, seq, type, at, pos, playing, rate);
}

/** Findings from one check, by id. */
function findings(db, id) {
  const [result] = runChecks({ db, only: [id] });
  assert.equal(result.error, undefined, `check ${id} threw: ${result.error}`);
  return result.findings;
}

// --- Each check fires on the shape it was written for -------------------------

test('impossible-overlap: two tabs Watched across the same minute', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', tabId: 1, title: 'One' });
  addView(db, { viewId: 'b', tabId: 2, title: 'Two' });
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 600_000 });
  addSegment(db, { viewId: 'b', from: T0 + 60_000, to: T0 + 300_000 });

  const found = findings(db, 'impossible-overlap');
  assert.equal(found.length, 1);
  assert.equal(found[0].costMs, 240_000);
});

test('impossible-overlap: the same tab is one tab, however many Views it had', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', tabId: 1 });
  addView(db, { viewId: 'b', tabId: 1 });
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 600_000 });
  addSegment(db, { viewId: 'b', from: T0 + 60_000, to: T0 + 300_000 });

  assert.deepEqual(findings(db, 'impossible-overlap'), []);
});

test('impossible-overlap: Picture-in-Picture is the honest exception', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', tabId: 1 });
  addView(db, { viewId: 'b', tabId: 2 });
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 600_000 });
  addSegment(db, { viewId: 'b', from: T0 + 60_000, to: T0 + 300_000 });
  addEvent(db, { viewId: 'a', seq: 1, type: 'pipEnter', at: T0 });

  assert.deepEqual(findings(db, 'impossible-overlap'), []);
});

test('phantom-wall-time: half an hour of Watched time the player slept through', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a' });
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 1_800_000, posStart: 0, posEnd: 12 });

  const found = findings(db, 'phantom-wall-time');
  assert.equal(found.length, 1);
  assert.match(found[0].summary, /banked 30\.0 min .* advanced 0\.2 min/);
});

test('phantom-wall-time: slow-motion playback is watching, not a frozen player', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a' });
  // 10 minutes of wall clock at 0.25x is 2.5 minutes of media — well under the
  // naive "half of wall clock" bar, and entirely legitimate.
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 600_000, posStart: 0, posEnd: 150 });
  addEvent(db, { viewId: 'a', seq: 1, type: 'ratechange', at: T0, rate: 0.25 });

  assert.deepEqual(findings(db, 'phantom-wall-time'), []);
});

test('blind-playing-stretch: "playing", then fifteen silent minutes', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a' });
  addEvent(db, { viewId: 'a', seq: 1, type: 'play', at: T0, pos: 0 });
  addEvent(db, { viewId: 'a', seq: 2, type: 'visible', at: T0 + 900_000, pos: 0 });

  const found = findings(db, 'blind-playing-stretch');
  assert.equal(found.length, 1);
  assert.equal(found[0].costMs, 900_000);
});

test('blind-playing-stretch: silence after a pause is just a paused video', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a' });
  addEvent(db, { viewId: 'a', seq: 1, type: 'pause', at: T0, pos: 30 });
  addEvent(db, { viewId: 'a', seq: 2, type: 'visible', at: T0 + 900_000, pos: 30 });

  assert.deepEqual(findings(db, 'blind-playing-stretch'), []);
});

test('position-reset-at-end: a Segment that ends where it cannot have ended', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a' });
  addSegment(db, { viewId: 'a', from: T0, to: T0 + 30_000, posStart: 300, posEnd: 0 });

  assert.equal(findings(db, 'position-reset-at-end').length, 1);
});

test('conflicting-duration: one video id, two lengths', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', videoId: 'same', durationSec: 600 });
  addView(db, { viewId: 'b', videoId: 'same', durationSec: 2177.9 });

  assert.equal(findings(db, 'conflicting-duration').length, 1);
});

test('title-across-videos: one title, two video ids', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', videoId: 'one', title: 'Shared title' });
  addView(db, { viewId: 'b', videoId: 'two', title: 'Shared title' });

  assert.equal(findings(db, 'title-across-videos').length, 1);
});

test('stale-open-view: open, and silent for days', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', open: 1 });
  addView(db, { viewId: 'b', open: 0 });
  addEvent(db, { viewId: 'a', seq: 1, type: 'pause', at: T0 });
  addEvent(db, { viewId: 'b', seq: 1, type: 'sample', at: T0 + 40 * 3_600_000 });

  assert.equal(findings(db, 'stale-open-view').length, 1);
});

test('sliding-window-duration: a 14-hour "length" is a DVR window', () => {
  const db = emptyDb();
  addView(db, { viewId: 'a', durationSec: 50_390 });

  assert.equal(findings(db, 'sliding-window-duration').length, 1);
});

// --- And an honest database says nothing at all ------------------------------

test('an afternoon of ordinary watching trips nothing', () => {
  const db = emptyDb();
  // Two videos, one after the other, in one tab. Beats every 5s, media keeping
  // pace with the wall clock, both Views closed behind them.
  for (const [index, viewId] of ['a', 'b'].entries()) {
    const start = T0 + index * 700_000;
    addView(db, { viewId, tabId: 7, videoId: `vid-${viewId}`, title: `Video ${viewId}`, startedAt: start });
    addSegment(db, { viewId, from: start, to: start + 600_000, posStart: 0, posEnd: 600 });
    addEvent(db, { viewId, seq: 1, type: 'play', at: start, pos: 0 });
    for (let beat = 1; beat <= 120; beat += 1) {
      addEvent(db, { viewId, seq: beat + 1, type: 'sample', at: start + beat * 5_000, pos: beat * 5, playing: 1 });
    }
    addEvent(db, { viewId, seq: 122, type: 'viewEnded', at: start + 600_000, pos: 600 });
  }

  const results = runChecks({ db });
  const noisy = results.filter((result) => result.findings.length || result.error);
  assert.deepEqual(
    noisy.map((result) => `${result.id}: ${result.error ?? result.findings[0]?.summary}`),
    [],
  );
});
