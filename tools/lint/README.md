# `wl lint` — what the data must never say

A read-only check over the WatchLogs database, asking whether what it recorded
is *possible*. Not part of the shipped app — a dev tool, like `tools/db-viewer`.

```sh
node tools/lint/cli.js
```

It reads the same database the app uses
(`~/Library/Application Support/WatchLogs/watchlogs.sqlite`), read-only, so the
app can be running and flushing at the same time.

```sh
node tools/lint/cli.js --since=1d              # only today's data
node tools/lint/cli.js --check=impossible-overlap
node tools/lint/cli.js --json | jq '.results[].findings'
node tools/lint/cli.js --help                  # lists every check
```

Exits non-zero when anything of `high` severity is found, so it can gate CI
against a captured database fixture.

The same checks render as the **Lint** tab in `tools/db-viewer`, live, next to
the tables they are complaining about.

## Why this exists

Four real bugs shipped in one week, and every one of them was invisible to the
test suite while being plainly visible in the data. They lived in the seams
*between* components that were each individually correct and individually
tested — the Extension knowing a tab was hidden while the App assumed it was
not; a duration read from one video landing on another's row.

A unit test can only encode the assumption you already had, so it cannot see a
seam. This can: it never asks whether a component did what it meant to, only
whether the result is something that could have happened.

The first run over four days of real data found **447 minutes of Watched time
that two tabs claim at once**. Nobody watched it, and nothing in the suite had
anything to say about it.

## Adding a check

Add an entry to `checks` in `checks.js`:

```js
{
  id: 'kebab-case-id',
  title: 'Short, in the user's terms',
  severity: 'high' | 'medium' | 'low',
  why: 'What this means, in plain language, about what the user did.',
  run({ db, sinceMs }) { return [ /* findings */ ]; },
}
```

Two rules, both learned the hard way:

- **State the rule as a fact about the world, not about the code.** "You can
  only look at one tab at a time" survives a refactor; "`isOpen` should be false
  here" does not.
- **Prove it does not cry wolf.** Every check has a test that it fires on the
  shape it was written for *and* a test that an honest database trips nothing —
  `checks.test.js`, including one whole afternoon of ordinary watching. An
  ignored check is worse than no check.

Do not re-derive Segments here. A check that had to recompute the answer to know
it was wrong would have its own bugs and would tell you nothing you could trust.
This reads what is stored and asks whether it is possible.

```sh
node --test tools/lint/checks.test.js
```
