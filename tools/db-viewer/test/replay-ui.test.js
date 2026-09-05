// The Replay tab, driven the way a person drives it.
//
// This exists because the flow broke in a way no API test could see: search and
// report rendered into the same element, so choosing one of three Views with
// the same title threw the other two away, and the search box was overwritten
// with a UUID you then had to clear before you could search again. Every
// request still answered 200.
//
// Playwright is borrowed from `extension/node_modules` rather than installed
// here: db-viewer's promise is that it runs with no `npm install`, and that
// stays true — only its tests need the browser.
//
//   node --test tools/db-viewer/test/replay-ui.test.js

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..');
const PLAYWRIGHT = path.join(REPO, 'extension', 'node_modules', 'playwright', 'index.mjs');
const REPLAY_BIN = path.join(REPO, 'app', '.build', 'debug', 'wl-replay');

const missing = !fs.existsSync(PLAYWRIGHT)
  ? 'playwright is not installed (cd extension && npm install)'
  : !fs.existsSync(REPLAY_BIN)
    ? 'wl-replay is not built (cd app && swift build --product wl-replay)'
    : null;

/**
 * A database with three Views sharing one title, which is the case that broke:
 * the search finds all three and only the report can tell them apart.
 */
function fixtureDb() {
  const file = path.join(os.tmpdir(), `wl-replay-ui-${process.pid}-${Date.now()}.sqlite`);
  const db = new DatabaseSync(file);
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

  const T0 = Date.UTC(2026, 8, 1, 20, 39, 0);
  const rows = [
    ['aaaaaaaa-0000-0000-0000-000000000001', 'MoErgo Go60 — long term review', 'go60a', 101, 0],
    ['bbbbbbbb-0000-0000-0000-000000000002', 'One Surprise After Another - MoErgo Go60 Review', 'go60b', 102, 60_000],
    ['cccccccc-0000-0000-0000-000000000003', 'MoErgo Go60 — long term review', 'go60a', 103, 120_000],
    ['dddddddd-0000-0000-0000-000000000004', 'Something else entirely', 'other', 104, 180_000],
  ];
  for (const [viewId, title, videoId, tabId, offset] of rows) {
    const start = T0 + offset;
    db.prepare(
      `INSERT INTO views (view_id, service, content_format, embedded, video_id, url, title,
                          author, duration_sec, metadata_source, adapter_id, tab_id, started_at_ms, open)
       VALUES (?, 'youtube', 'standard', 0, ?, 'https://youtube.com/watch?v=' || ?, ?,
               'A Channel', 600.0, 'mediaSession', 'youtube', ?, ?, 0)`
    ).run(viewId, videoId, videoId, title, tabId, start);
    db.prepare(
      `INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
       VALUES (?, 'watched', ?, ?, 0, 30, 0)`
    ).run(viewId, start, start + 30_000);
    const events = [
      [1, 'mediaFound', start, 0, null],
      [2, 'play', start, 0, null],
      [3, 'sample', start + 5000, 5, 1],
      [4, 'viewEnded', start + 30_000, 30, null],
    ];
    for (const [seq, type, t, pos, playing] of events) {
      db.prepare(
        `INSERT INTO raw_events (view_id, seq, type, t_ms, pos, playing, visible) VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).run(viewId, seq, type, t, pos, playing, playing);
    }
  }
  db.close();
  return file;
}

// `skip` is only set when there is a reason: passing `null` makes node's runner
// report the whole suite as skipped even though every subtest ran, which would
// let this file rot green.
const options = { timeout: 120_000, ...(missing ? { skip: missing } : {}) };

test('Replay tab', options, async (t) => {
  const { chromium } = await import(PLAYWRIGHT);
  const dbFile = fixtureDb();
  const port = 5300 + (process.pid % 200);
  const server = spawn('node', [path.join(REPO, 'tools', 'db-viewer', 'server.js'), `--db=${dbFile}`, `--port=${port}`], {
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  const serverErrors = [];
  server.stderr.on('data', (chunk) => serverErrors.push(String(chunk)));

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));
  page.on('console', (message) => {
    if (message.type() === 'error') pageErrors.push(message.text());
  });

  t.after(async () => {
    await browser.close();
    server.kill();
    for (const suffix of ['', '-wal', '-shm']) fs.rmSync(dbFile + suffix, { force: true });
  });

  // The server needs a moment to bind before the first navigation.
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      await page.goto(`http://127.0.0.1:${port}/`);
      break;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  await page.click('#replay-item');
  await page.waitForSelector('.replay-list tr');

  const rows = () => page.locator('#replay-results tr');
  const search = async (query) => {
    await page.fill('#replay-find', query);
    await page.waitForTimeout(500);
  };
  const reportedViewId = async () =>
    (await page.locator('#replay-body .replay-section h3 .mono').first().textContent()).trim();

  await t.test('opening the tab lists the most recent Views', async () => {
    assert.equal(await rows().count(), 4);
    assert.match(await page.locator('#replay-count').textContent(), /most recent/);
  });

  await t.test('a search lists every match, not just the first', async () => {
    await search('moergo');
    assert.equal(await rows().count(), 3);
    assert.equal(await page.locator('#replay-count').textContent(), '3 Views match');
  });

  await t.test('picking a match leaves the other matches on screen', async () => {
    await rows().first().click();
    await page.waitForSelector('#replay-body .replay-section');
    assert.equal(await rows().count(), 3, 'the results survived choosing one');
    assert.equal(await page.inputValue('#replay-find'), 'moergo', 'the query was not overwritten');
    assert.equal(await page.locator('#replay-results tr.selected').count(), 1);
  });

  await t.test('each match opens its own View, not the one before it', async () => {
    const seen = [];
    for (let index = 0; index < 3; index += 1) {
      await rows().nth(index).click();
      await page.waitForSelector('#replay-body .replay-section');
      await page.waitForFunction(
        (previous) => {
          const node = document.querySelector('#replay-body .replay-section h3 .mono');
          return node && node.textContent.trim() !== previous;
        },
        seen.at(-1) ?? '',
        { timeout: 15_000 },
      );
      seen.push(await reportedViewId());
    }
    assert.equal(new Set(seen).size, 3, `expected three distinct Views, got ${JSON.stringify(seen)}`);
  });

  await t.test('the selected row is the one being reported', async () => {
    await rows().nth(1).click();
    await page.waitForTimeout(700);
    const selected = await page.locator('#replay-results tr.selected td').first().textContent();
    assert.ok((await reportedViewId()).startsWith(selected.replace('→ ', '').trim()));
  });

  await t.test('two Views sharing a title are told apart by the report', async () => {
    await search('long term review');
    assert.equal(await rows().count(), 2, 'both Views of that title match');
    await rows().nth(0).click();
    await page.waitForSelector('#replay-body .replay-section');
    const first = await reportedViewId();
    await rows().nth(1).click();
    await page.waitForFunction(
      (previous) => {
        const node = document.querySelector('#replay-body .replay-section h3 .mono');
        return node && node.textContent.trim() !== previous;
      },
      first,
      { timeout: 15_000 },
    );
    assert.notEqual(await reportedViewId(), first);
  });

  await t.test('a new search clears the report it does not belong to', async () => {
    await search('something else');
    assert.equal(await rows().count(), 1);
    assert.equal((await page.locator('#replay-body').textContent()).trim(), '');
    assert.equal(await page.locator('#replay-results tr.selected').count(), 0);
  });

  await t.test('words may arrive in any order and punctuation is forgiven', async () => {
    await search('review go60');
    assert.equal(await rows().count(), 3);
    await search('MoErgo Go60 - long term review');
    assert.equal(await rows().count(), 2, 'an ordinary hyphen finds the em-dash title');
  });

  await t.test('a query that matches nothing says why', async () => {
    await search('mooergo');
    assert.equal(await rows().count(), 0);
    const message = await page.locator('#replay-results').textContent();
    assert.match(message, /Nothing matches/);
    assert.match(message, /matching is literal/i);
  });

  await t.test('clearing the query returns to the most recent Views', async () => {
    await search('');
    assert.equal(await rows().count(), 4);
  });

  await t.test('a view_id in any table opens that View, keeping the query', async () => {
    await search('moergo');
    await page.click('#replay-item');
    const tables = page.locator('#table-list li');
    for (let index = 0; index < (await tables.count()); index += 1) {
      if ((await tables.nth(index).textContent()).includes('segments')) {
        await tables.nth(index).click();
        break;
      }
    }
    await page.waitForSelector('td.linked');
    const clicked = (await page.locator('td.linked').first().textContent()).trim();
    await page.locator('td.linked').first().click();
    await page.waitForSelector('#replay-body .replay-section');
    assert.equal(await reportedViewId(), clicked);
    assert.equal(await page.inputValue('#replay-find'), 'moergo', 'the id did not overwrite the query');
  });

  await t.test('nothing threw along the way', () => {
    assert.deepEqual(pageErrors, []);
    assert.deepEqual(serverErrors, []);
  });
});
