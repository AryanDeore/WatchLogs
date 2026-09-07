# Bug triage template

Copy this into a new issue.

## 1) Symptom (what user sees)
- Time:
- Screen/pane:
- Exact row text:
- Expected:
- Actual:

## 2) Repro steps (small and exact)
1.
2.
3.

## 3) Scope guess
- [ ] Extension capture
- [ ] App ingest/read model
- [ ] UI rendering only
- [ ] Unknown yet

## 4) 10-minute data provenance pass

### A. Network truth
- Endpoint checked:
- video id found:
- duration found:

### B. Extension trace / bundle
- Extension version:
- `open` entry:
- `change_video` entry:
- `metadata_change` entry:

### C. App DB snapshot
- DB row video id:
- DB row title/author:
- DB row duration_sec:
- watched_ms:

### D. UI result
- bar length/label behavior:

## 5) Root cause hypothesis
- One sentence:

## 6) Fix options (two ways)
- Way 1:
  - pros:
  - cons:
- Way 2:
  - pros:
  - cons:

## 7) Chosen fix
- What we chose:
- Why:

## 8) Acceptance checks
- [ ] Repro now passes
- [ ] No regression in related area
- [ ] Versions bumped if app/extension changed
- [ ] Tests added/updated

## 9) Artifacts
- Debug bundle file:
- DB query output:
- Screenshot(s):
