#!/usr/bin/env node
// `wl lint` — hold the stored data up against what it is not allowed to say.
//
// A debug tool, not part of the shipped app. It opens the database read-only,
// so it is safe to run while the app is writing.
//
// Usage:
//   node tools/lint/cli.js [--db=<path>] [--since=7d] [--check=<id>[,<id>]]
//                          [--limit=<n>] [--json] [--quiet]
//
// Exits 1 when anything of `high` severity is found, so it can gate CI against
// a captured database fixture.

import { openReadOnly, parseArgs, parseSince, resolveDbPath } from '../lib/database.js';
import { checks, implicatedWatchedMs, runChecks } from './checks.js';

const BADGE = { high: '\x1b[31m HIGH \x1b[0m', medium: '\x1b[33m MED  \x1b[0m', low: '\x1b[90m LOW  \x1b[0m' };
const DIM = '\x1b[90m';
const BOLD = '\x1b[1m';
const OFF = '\x1b[0m';

const args = parseArgs(process.argv.slice(2));

if (args.help || args.h) {
  console.log('Checks the WatchLogs database against the things it must never say.\n');
  console.log('  --db=<path>         database to read (default: the app\'s own)');
  console.log('  --since=7d|36h|all  only look at recent data (default: all)');
  console.log('  --check=<id>,<id>   run only these checks');
  console.log('  --limit=<n>         examples printed per check (default: 5)');
  console.log('  --json              machine-readable output');
  console.log('  --quiet             totals only, no examples\n');
  console.log('Checks:');
  for (const check of checks) console.log(`  ${check.severity.padEnd(6)} ${check.id.padEnd(24)} ${check.title}`);
  process.exit(0);
}

const dbPath = resolveDbPath(args);
const db = openReadOnly(dbPath);
const sinceMs = parseSince(args.since);
const only = args.check ? args.check.split(',').map((id) => id.trim()) : null;
const limit = Number(args.limit ?? 5);

if (only) {
  const unknown = only.filter((id) => !checks.some((check) => check.id === id));
  if (unknown.length) {
    console.error(`No such check: ${unknown.join(', ')}. Run with --help to list them.`);
    process.exit(1);
  }
}

const results = runChecks({ db, sinceMs, only });

if (args.json) {
  console.log(JSON.stringify({ database: dbPath, since: args.since ?? 'all', results }, null, 2));
} else {
  report(results);
}

process.exit(results.some((result) => result.severity === 'high' && result.findings.length) ? 1 : 0);

// --- Reporting ---------------------------------------------------------------
function report(results) {
  console.log(`${DIM}${dbPath}${OFF}`);
  console.log(`${DIM}window: ${args.since ?? 'all'}${OFF}\n`);

  const found = results.filter((result) => result.findings.length || result.error);
  if (!found.length) {
    console.log('Nothing to report — every check passed.');
    return;
  }

  for (const result of found) {
    if (result.error) {
      console.log(`${BADGE[result.severity]} ${BOLD}${result.title}${OFF}  ${DIM}(${result.id})${OFF}`);
      console.log(`       could not run: ${result.error}\n`);
      continue;
    }

    const cost = result.costMs ? `  ${DIM}·${OFF} ${(result.costMs / 60_000).toFixed(1)} min in doubt` : '';
    console.log(
      `${BADGE[result.severity]} ${BOLD}${result.title}${OFF}  ${DIM}(${result.id})${OFF}\n` +
        `       ${result.findings.length} found${cost}`
    );
    console.log(`${DIM}${wrap(result.why, 7)}${OFF}`);

    if (!args.quiet) {
      for (const finding of result.findings.slice(0, limit)) console.log(`       · ${finding.summary}`);
      if (result.findings.length > limit) {
        console.log(`       ${DIM}… and ${result.findings.length - limit} more${OFF}`);
      }
    }
    console.log();
  }

  const { implicatedMs, totalMs } = implicatedWatchedMs(db, found);
  console.log(
    `${BOLD}${found.reduce((n, r) => n + r.findings.length, 0)} findings${OFF} across ${found.length} checks` +
      (implicatedMs && totalMs
        ? ` · ${(implicatedMs / 60_000).toFixed(0)} min of ${(totalMs / 60_000).toFixed(0)} min recorded ` +
          `(${((implicatedMs / totalMs) * 100).toFixed(0)}%) sits in a Segment some check flags`
        : '')
  );
}

/** Wrap `why` to a readable column, indented under its heading. */
function wrap(text, indent) {
  const pad = ' '.repeat(indent);
  const words = text.split(/\s+/);
  const lines = [];
  let line = '';
  for (const word of words) {
    if ((line + word).length > 88) {
      lines.push(line.trimEnd());
      line = '';
    }
    line += `${word} `;
  }
  if (line.trim()) lines.push(line.trimEnd());
  return lines.map((l) => pad + l).join('\n');
}
