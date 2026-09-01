# One storage key per Event, one writer per key

The Extension's outbound buffer lives in `chrome.storage.local` and has two writers in two processes: the page helper appends Events as they happen, and the background worker deletes them once the App has Ack'd them. `chrome.storage` has no transaction and no compare-and-swap, so anything read-modify-written by both sides can lose an update — and the update it loses is a captured Event. We decided the buffer stores **one Event per key**, with **exactly one writer per key**: `wl:view:<viewId>` and `wl:evt:<viewId>:<seq>` are written only by the frame that owns the View, `wl:ack:<viewId>` only by the worker. Pruning is then a targeted `remove` of keys, never a rewrite of a shared value.

The worker deletes frame-owned keys in one case only — a View that is closed *and* fully Ack'd, which no frame will write to again.

## Considered options

- **One key per View holding its Event array.** The obvious layout, and the one the prototype's in-memory session suggests. Rejected: the prune is then `get` → filter → `set` on the same key the frame is appending to. An Event captured during the POST is inside the window and is silently dropped — the exact data loss the on-disk buffer exists to prevent.
- **The worker owns the buffer; frames send Events to it by message.** One writer, no races. Rejected: it makes capture depend on a service worker that Chromium evicts aggressively. Every message is a worker revival, and an Event captured while the worker is starting has nowhere to live. Issue #18 (user story 10) puts the buffer on the page-helper side for this reason.

## Consequences

- Reading the buffer is a `storage.local.get(null)` and a rehydrate, not a single key read. Cheap at this scale — the buffer holds seconds-to-minutes of Events, pruned on every Ack.
- Event keys are zero-padded (`seq` to 9 digits) so string order is `seq` order.
- A crashed browser leaves whole, well-formed keys behind rather than a half-written array, which is what makes crash recovery a scan for `open` Views rather than a repair.
- Recovery needs to tell "a View from the run that died" from "a View a restored tab just opened". The worker keeps a run id in `chrome.storage.session` (which survives worker eviction but not the browser closing), stamps every View header with it, and answers the page helper's opening `hello` only after it has closed the previous run's Views — so a restored tab can never be recovered out from under itself.
