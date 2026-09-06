// Where the database is and how a dev tool opens it. Shared by every tool in
// this directory so "the WatchLogs database" means one thing, in one place.
//
// Everything here opens the file **read-only**: the app is normally running and
// writing while a tool reads, and a debug tool must never be able to corrupt
// the data it is being used to explain.

import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

/** Mirrors `EventStore.defaultPath()` in WatchLogsKit. */
export function defaultDbPath() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'WatchLogs', 'watchlogs.sqlite');
}

/** `--name=value` flags, in the order-independent form every tool here takes. */
export function parseArgs(argv) {
  const out = {};
  for (const arg of argv) {
    const match = /^--([a-zA-Z-]+)(?:=(.*))?$/.exec(arg);
    if (match) out[match[1]] = match[2] ?? 'true';
  }
  return out;
}

/**
 * The database path a tool should use: `--db`, then `WATCHLOGS_DB`, then the
 * app's own default.
 */
export function resolveDbPath(args = {}) {
  return args.db || process.env.WATCHLOGS_DB || defaultDbPath();
}

/**
 * Open the database read-only, or exit with a message a human can act on.
 * Tools are run by hand, so a stack trace is never the right answer here.
 */
export function openReadOnly(dbPath) {
  if (!fs.existsSync(dbPath)) {
    console.error(`No database at ${dbPath}`);
    console.error('Run the WatchLogs app at least once so it creates the database, or pass --db=<path>.');
    process.exit(1);
  }
  try {
    return new DatabaseSync(dbPath, { readOnly: true });
  } catch (err) {
    console.error(`Could not open ${dbPath} read-only: ${err.message}`);
    process.exit(1);
  }
}

/**
 * A window like `7d`, `36h`, `90m` as milliseconds — or `null` for "everything".
 * Tools take it as `--since`, because "is this still happening?" is a different
 * question from "has this ever happened?".
 */
export function parseSince(value) {
  if (!value || value === 'all') return null;
  const match = /^(\d+(?:\.\d+)?)([dhm])$/.exec(String(value).trim());
  if (!match) {
    console.error(`Could not read --since=${value}. Use a window like 7d, 36h or 90m, or "all".`);
    process.exit(1);
  }
  const scale = { d: 86_400_000, h: 3_600_000, m: 60_000 }[match[2]];
  return Number(match[1]) * scale;
}
