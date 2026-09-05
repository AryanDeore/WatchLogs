#!/usr/bin/env node
// Local read-only viewer for the WatchLogs SQLite database — a debug tool,
// not part of the shipped app. Opens the database read-only (node:sqlite)
// so it can be run safely while the app is writing to it, and serves a
// small static frontend + JSON API on localhost. No npm dependencies:
// everything here is Node's standard library, matching the extension's
// no-build-step convention.
//
// Usage:
//   node tools/db-viewer/server.js [--db=<path>] [--port=<n>]
//   WATCHLOGS_DB=<path> WATCHLOGS_DB_VIEWER_PORT=<n> node tools/db-viewer/server.js

import { DatabaseSync } from 'node:sqlite';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');

function parseArgs(argv) {
  const out = {};
  for (const arg of argv) {
    const match = /^--([a-zA-Z-]+)=(.*)$/.exec(arg);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));

function defaultDbPath() {
  // Mirrors EventStore.defaultPath() in WatchLogsKit.
  return path.join(os.homedir(), 'Library', 'Application Support', 'WatchLogs', 'watchlogs.sqlite');
}

const dbPath = args.db || process.env.WATCHLOGS_DB || defaultDbPath();
const port = Number(args.port || process.env.WATCHLOGS_DB_VIEWER_PORT || 5183);

if (!fs.existsSync(dbPath)) {
  console.error(`No database at ${dbPath}`);
  console.error('Run the WatchLogs app at least once so it creates the database, or pass --db=<path>.');
  process.exit(1);
}

let db;
try {
  db = new DatabaseSync(dbPath, { readOnly: true });
} catch (err) {
  console.error(`Could not open ${dbPath} read-only: ${err.message}`);
  process.exit(1);
}

// --- Schema introspection -------------------------------------------------

function listTables() {
  return db
    .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    .all()
    .map((row) => row.name);
}

function tableColumns(table) {
  // `table` must already be validated against listTables() by the caller.
  return db.prepare(`PRAGMA table_info("${table}")`).all().map((row) => ({
    name: row.name,
    type: row.type,
    pk: row.pk > 0,
  }));
}

function assertValidTable(name) {
  if (!listTables().includes(name)) {
    const err = new Error(`no such table: ${name}`);
    err.statusCode = 404;
    throw err;
  }
}

function assertValidColumn(table, columns, name) {
  if (!columns.some((c) => c.name === name)) {
    const err = new Error(`no such column: ${name}`);
    err.statusCode = 400;
    throw err;
  }
}

// Escapes % and _ (LIKE wildcards) and the escape character itself so a
// filter value is always matched literally, then wraps it for substring
// matching.
function likeParam(value) {
  return `%${String(value).replace(/[\\%_]/g, '\\$&')}%`;
}

// --- Route handlers --------------------------------------------------------

function handleTables() {
  const tables = listTables().map((name) => {
    const { n } = db.prepare(`SELECT COUNT(*) AS n FROM "${name}"`).get();
    return { name, count: n };
  });
  return { tables };
}

function handleColumns(table) {
  assertValidTable(table);
  return { columns: tableColumns(table) };
}

function handleRows(table, query) {
  assertValidTable(table);
  const columns = tableColumns(table);

  const limit = Math.min(Math.max(parseInt(query.get('limit') ?? '100', 10) || 100, 1), 1000);
  const offset = Math.max(parseInt(query.get('offset') ?? '0', 10) || 0, 0);

  let sortBy = query.get('sortBy') || 'rowid';
  if (sortBy !== 'rowid') assertValidColumn(table, columns, sortBy);
  const sortDir = query.get('sortDir') === 'asc' ? 'ASC' : 'DESC';

  let filters = {};
  const rawFilters = query.get('filters');
  if (rawFilters) {
    try {
      filters = JSON.parse(rawFilters);
    } catch {
      const err = new Error('filters must be JSON');
      err.statusCode = 400;
      throw err;
    }
  }

  const whereClauses = [];
  const whereParams = [];
  for (const [col, value] of Object.entries(filters)) {
    if (value === '' || value == null) continue;
    if (col === '__any__') {
      const anyClauses = columns.map((c) => `CAST("${c.name}" AS TEXT) LIKE ? ESCAPE '\\'`);
      whereClauses.push(`(${anyClauses.join(' OR ')})`);
      for (let i = 0; i < columns.length; i++) whereParams.push(likeParam(value));
      continue;
    }
    assertValidColumn(table, columns, col);
    whereClauses.push(`CAST("${col}" AS TEXT) LIKE ? ESCAPE '\\'`);
    whereParams.push(likeParam(value));
  }
  const whereSql = whereClauses.length ? `WHERE ${whereClauses.join(' AND ')}` : '';

  const total = db.prepare(`SELECT COUNT(*) AS n FROM "${table}" ${whereSql}`).get(...whereParams).n;

  const colList = columns.map((c) => `"${c.name}"`).join(', ');
  const sortCol = sortBy === 'rowid' ? 'rowid' : `"${sortBy}"`;
  const rows = db
    .prepare(
      `SELECT rowid AS __rowid__, ${colList} FROM "${table}" ${whereSql} ORDER BY ${sortCol} ${sortDir}, rowid ${sortDir} LIMIT ? OFFSET ?`
    )
    .all(...whereParams, limit, offset);

  return { rows, total, columns };
}

// --- Tiny static file server ------------------------------------------------

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

function serveStatic(req, res) {
  const reqPath = req.url === '/' ? '/index.html' : req.url;
  const filePath = path.join(PUBLIC_DIR, path.normalize(reqPath).replace(/^(\.\.[/\\])+/, ''));
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] || 'application/octet-stream' });
    res.end(data);
  });
}

function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(data);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);

  try {
    if (url.pathname === '/api/tables') {
      return sendJson(res, 200, handleTables());
    }
    const columnsMatch = /^\/api\/tables\/([^/]+)\/columns$/.exec(url.pathname);
    if (columnsMatch) {
      return sendJson(res, 200, handleColumns(decodeURIComponent(columnsMatch[1])));
    }
    const rowsMatch = /^\/api\/tables\/([^/]+)\/rows$/.exec(url.pathname);
    if (rowsMatch) {
      return sendJson(res, 200, handleRows(decodeURIComponent(rowsMatch[1]), url.searchParams));
    }
    if (url.pathname.startsWith('/api/')) {
      return sendJson(res, 404, { error: 'not found' });
    }
    return serveStatic(req, res);
  } catch (err) {
    return sendJson(res, err.statusCode || 500, { error: err.message });
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`WatchLogs DB viewer — reading ${dbPath}`);
  console.log(`http://localhost:${port}`);
});
