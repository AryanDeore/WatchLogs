## Agent skills

### Issue tracker

Issues and specs live in the repo's GitHub Issues (AryanDeore/WatchLogs), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Extension versioning

After any change under `extension/`, bump the extension version before commit.

- Update the version in `extension/manifest.json` (and any matching package metadata if needed).
- Patch bump for normal changes: `0.1.0` → `0.1.1`.

### App versioning

After any change under `app/`, bump the app version before commit.

- Update the version string in app sources where exposed to users/API (`WatchLogsApp.swift`, `AppDelegate.swift`, `SettingsView.swift`, and related tests if needed).
- Patch bump for normal changes: `0.1.0` → `0.1.1`.


## How to explain things to me

When walking me through a decision, a tradeoff, or how something works:

- Plain language only. No jargon, or define it in the same breath.
- Start with a concrete scenario I'd actually hit — specific times, specific
  actions — before naming any abstract concept.
- Lay out choices as "two ways to handle it," each in plain terms.
- End with your recommendation and a one-line why.
- Always prefer a worked example over a general description.
