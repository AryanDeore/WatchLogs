// The Replay tab's data source: the `wl-replay` binary, run per request.
//
// This shells out rather than reimplementing anything, and that is the whole
// design. `wl-replay` calls the shipped `SegmentComputer` and the shipped read
// model; a JavaScript port of either would have its own bugs and could only
// ever tell you about itself. The cost is that the binary has to be built —
// which is a message this can give clearly, unlike a wrong answer.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');

/**
 * Where `swift build` leaves the binary. Debug first: this is a dev tool run
 * next to a dev build, and a stale release binary that happens to exist would
 * quietly answer with the wrong build's Segment computation — the one thing the
 * stored-vs-recomputed comparison must never get wrong.
 */
const CANDIDATES = [
  process.env.WATCHLOGS_REPLAY_BIN,
  path.join(REPO, 'app', '.build', 'debug', 'wl-replay'),
  path.join(REPO, 'app', '.build', 'release', 'wl-replay'),
].filter(Boolean);

export function replayBinary() {
  return CANDIDATES.find((candidate) => fs.existsSync(candidate)) ?? null;
}

const NOT_BUILT =
  'wl-replay is not built. Run:  cd app && swift build --product wl-replay';

/** Run the binary and parse its JSON, turning every failure into an Error. */
function run(args, { timeoutMs = 30_000 } = {}) {
  const binary = replayBinary();
  if (!binary) {
    const err = new Error(NOT_BUILT);
    err.statusCode = 503;
    return Promise.reject(err);
  }

  return new Promise((resolve, reject) => {
    execFile(binary, [...args, '--json'], { timeout: timeoutMs, maxBuffer: 32 * 1024 * 1024 }, (error, stdout, stderr) => {
      // A non-zero exit still carries a JSON error body — "no View matches" is
      // an answer, not a crash — so parse before deciding this went wrong.
      let parsed = null;
      try {
        parsed = JSON.parse(stdout);
      } catch {
        /* fall through to the error path below */
      }
      if (parsed?.error) {
        const err = new Error(parsed.error);
        err.statusCode = 404;
        return reject(err);
      }
      if (parsed) return resolve(parsed);

      const err = new Error(
        error?.killed
          ? 'wl-replay timed out'
          : `wl-replay failed: ${(stderr || error?.message || 'no output').toString().trim().slice(0, 400)}`
      );
      err.statusCode = 500;
      return reject(err);
    });
  });
}

/** The full report for one View. */
export function replayView(dbPath, viewId) {
  return run([`--db=${dbPath}`, viewId]);
}

/** Views matching a query, or the most recent ones when the query is empty. */
export function findViews(dbPath, query, limit = 25) {
  const args = [`--db=${dbPath}`, `--limit=${limit}`];
  args.push(query ? `--find=${query}` : '--recent');
  return run(args);
}
