// The background worker. It owns exactly three things: POST the buffered Flush,
// fold the Ack back into the buffer, and hold the pairing string.
//
// Everything else — capture, the 5-second cadence, the `seq` — belongs to the
// page helper, so this worker is free to be evicted between Flushes. It is
// woken by the page helper's `sendMessage`, POSTs, and dies. A `chrome.alarms`
// sweep every 30 s is the backstop that revives it to drain a buffer nobody has
// nudged (a throttled tab, a tab that closed mid-Flush). Note that an unpacked
// extension gets no alarms floor of its own — 30 s is the cadence we ask for,
// not one the browser guarantees.

import { parsePairingString, baseUrl } from "./src/pairing.js";
import { interpretFlushResponse } from "./src/flush.js";
import { INITIAL_STATE, reduce } from "./src/state.js";
import { apply, buildFlush } from "./src/capture.js";
import { prunePlan, rehydrate, staleOpenViewIds, viewKey, writesFor } from "./src/buffer.js";
import { uuidv4 } from "./src/ids.js";
import { capturesPrivateWindowsForHello } from "./src/settings.js";

const PAIRING_KEY = "pairing";
const STATE_KEY = "connectionState";
const INSTANCE_KEY = "extInstanceId";
const PENDING_FLUSH_KEY = "pendingFlushId";
const RUN_KEY = "runId";
const SWEEP_ALARM = "watchlogs-sweep";
/** The backstop cadence: 30 s, the shortest `chrome.alarms` will honour. */
const SWEEP_MINUTES = 0.5;

// --- Waking up ----------------------------------------------------------------

chrome.runtime.onInstalled.addListener(() => {
  ensureSweep();
  void flushNow({ reconcile: true });
});

chrome.runtime.onStartup.addListener(() => {
  ensureSweep();
  void flushNow({ reconcile: true });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SWEEP_ALARM) void flushNow({ reconcile: true });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message?.type) {
    case "hello":
      // The page helper's handshake. Answering it means crash recovery for this
      // browser run has already finished. The worker also owns the private-tab
      // decision because only its sender metadata identifies the tab as incognito.
      void helloFor(sender).then(sendResponse);
      return true;
    case "flush":
      void flushNow().then(() => sendResponse({ ok: true }));
      return true;
    case "pair":
      void pair(message.pairingString).then(sendResponse);
      return true;
    case "getState":
      void readState().then(sendResponse);
      return true;
    default:
      return false;
  }
});

function ensureSweep() {
  chrome.alarms.create(SWEEP_ALARM, { periodInMinutes: SWEEP_MINUTES, delayInMinutes: SWEEP_MINUTES });
}

async function helloFor(sender) {
  const [runId, settings] = await Promise.all([
    currentRun(),
    chrome.storage.local.get(PAIRING_KEY),
  ]);
  const appResponse = await privateWindowSettingFromApp(settings[PAIRING_KEY]);
  return {
    runId,
    tabId: sender.tab?.id ?? 0,
    incognito: sender.tab?.incognito === true,
    capturePrivateWindows: capturesPrivateWindowsForHello(appResponse),
  };
}

async function privateWindowSettingFromApp(rawPairing) {
  if (!rawPairing) return null;
  try {
    const pairing = parsePairingString(rawPairing);
    const response = await fetch(`${baseUrl(pairing)}/v1/settings`, {
      headers: { Authorization: `Bearer ${pairing.token}` },
    });
    const settings = await response.json();
    return { ok: response.ok, capturePrivateWindows: settings.capturePrivateWindows };
  } catch {
    return null;
  }
}

// --- Which browser run is this --------------------------------------------------

let runPromise = null;

/**
 * The id of this browser run, minted once and kept in session storage — which
 * survives the worker being evicted but not the browser being closed or killed.
 * Finding none is therefore the definition of a fresh run, and any View still
 * marked open in the on-disk buffer belongs to the run before it.
 */
function currentRun() {
  return (runPromise ??= startRun());
}

async function startRun() {
  const existing = (await chrome.storage.session.get(RUN_KEY))[RUN_KEY];
  if (existing) return existing;

  const runId = uuidv4();
  await chrome.storage.session.set({ [RUN_KEY]: runId });
  await recoverOpenViews(runId);
  return runId;
}

/**
 * Close the Views a dead browser left open, stamped at their last `sample` —
 * "we know it was still playing then, and we can't honestly claim a second
 * more".
 */
async function recoverOpenViews(runId) {
  const items = await chrome.storage.local.get(null);
  const stale = staleOpenViewIds(items, runId);
  if (stale.length === 0) return;

  await closeOpenViews(items, stale, "crash-recovered");
}

/**
 * Close Views whose tab is gone. A frame gets one last chance to write its own
 * `viewEnded` on `pagehide`, but a closing tab often dies before that write
 * lands — and a View left open would otherwise sit in the buffer until the next
 * browser run reported it as `crash-recovered`. Reconciling against the live
 * tabs on every sweep is what makes `tab-closed` a reason the App ever sees.
 */
async function recoverClosedTabs(items) {
  const openViews = Object.entries(items)
    .filter(([key, header]) => key.startsWith("wl:view:") && header?.open && header?.tabId > 0);
  if (openViews.length === 0) return;

  const live = new Set((await chrome.tabs.query({})).map((tab) => tab.id));
  const orphaned = openViews
    .filter(([, header]) => !live.has(header.tabId))
    .map(([, header]) => header.viewId);
  if (orphaned.length === 0) return;

  // Stamped at the last `sample` for the same reason a crash is: nothing
  // observed the moment the tab went away.
  await closeOpenViews(items, orphaned, "tab-closed");
}

/** Close `viewIds` at their last `sample` and write back only what that added. */
async function closeOpenViews(items, viewIds, reason) {
  const capture = rehydrate(items, { now: Date.now() });
  capture.order = capture.order.filter((viewId) => viewIds.includes(viewId));
  apply(capture, { type: "END_OPEN_VIEWS", reason });

  const writes = {};
  for (const viewId of capture.order) {
    Object.assign(
      writes,
      writesFor(capture.views[viewId], { fromSeq: items[viewKey(viewId)].lastSeq }),
    );
  }
  await chrome.storage.local.set(writes);
}

// --- Flushing ---------------------------------------------------------------------

/** One request in flight at a time (ADR 0002). */
let inFlight = false;

/**
 * @param {{ reconcile?: boolean }} [options]
 *   `reconcile` also checks the buffer against the browser's live tabs. That is
 *   the sweep's job, not something to redo on every 5-second Flush.
 */
async function flushNow({ reconcile = false } = {}) {
  if (inFlight) return;
  inFlight = true;
  // The App's refresh button (issue #35 §3) has no push channel to hit us
  // with, so it rides its hint on the next Ack instead. Read outside the
  // `finally` so the follow-up flush only starts once `inFlight` is clear.
  let flushAgain = false;
  try {
    await currentRun();
    const raw = (await chrome.storage.local.get(PAIRING_KEY))[PAIRING_KEY];
    if (!raw) return; // not paired (or un-paired by a 401) — keep buffering

    let pairing;
    try {
      pairing = parsePairingString(raw);
    } catch {
      await writeState({ status: "needs-pairing", reason: "bad-pairing-string", at: Date.now() });
      return;
    }

    if (reconcile) await recoverClosedTabs(await chrome.storage.local.get(null));
    const items = await chrome.storage.local.get(null);
    const capture = rehydrate(items, { now: Date.now() });
    // A resend after a lost Ack reuses the flushId, so the App replays its
    // original Ack instead of storing the batch twice.
    const flushId = items[PENDING_FLUSH_KEY] ?? uuidv4();
    const body = buildFlush(capture, { flushId, sentAt: Date.now(), agent: await agentInfo() });
    if (body.views.length > 0 && items[PENDING_FLUSH_KEY] !== flushId) {
      await chrome.storage.local.set({ [PENDING_FLUSH_KEY]: flushId });
    }

    const { status, payload } = await post(pairing, body);
    const decision = interpretFlushResponse(status, payload, flushId);

    if (decision.outcome === "accepted") {
      await prune(items, decision.ack);
      await chrome.storage.local.remove(PENDING_FLUSH_KEY);
      flushAgain = decision.ack?.flushAgain === true;
    } else if (decision.outcome === "re-pair") {
      // Stop: clear the sweep and forget the pairing so nothing keeps hammering
      // the App with a dead token. The buffer stays — it is the user's data, and
      // it goes out once they paste a fresh string.
      await chrome.alarms.clear(SWEEP_ALARM);
      await chrome.storage.local.remove(PAIRING_KEY);
    }
    await writeState(reduce(await readState(), decision, Date.now()));
  } finally {
    inFlight = false;
  }
  // The App only ever asks once per hint (it clears its own flag on the way
  // out), so this can't loop: the follow-up flush's Ack won't carry it again.
  if (flushAgain) void flushNow();
}

async function post(pairing, body) {
  try {
    const response = await fetch(`${baseUrl(pairing)}/v1/flush`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${pairing.token}`,
      },
      body: JSON.stringify(body),
    });
    return { status: response.status, payload: await response.json().catch(() => null) };
  } catch {
    return { status: 0, payload: null };
  }
}

/** Everything the App has taken responsibility for leaves the buffer. */
async function prune(items, ack) {
  const plan = prunePlan(items, ack);
  if (Object.keys(plan.set).length > 0) await chrome.storage.local.set(plan.set);
  if (plan.remove.length > 0) await chrome.storage.local.remove(plan.remove);
}

// --- Pairing (called from the options page) --------------------------------------

async function pair(pairingString) {
  let pairing;
  try {
    pairing = parsePairingString(pairingString);
  } catch (error) {
    return { ok: false, error: String(error.message ?? error) };
  }

  // Confirm the App is really there before we store anything.
  try {
    const ping = await fetch(`${baseUrl(pairing)}/v1/ping`);
    const info = await ping.json();
    if (!ping.ok || info?.contract !== "v1") {
      return { ok: false, error: "that App did not answer /v1/ping with contract v1" };
    }
  } catch {
    return { ok: false, error: "could not reach the App at that host and port" };
  }

  await chrome.storage.local.set({ [PAIRING_KEY]: pairingString.trim() });
  ensureSweep();
  await flushNow();
  return { ok: true };
}

// --- Storage helpers ---------------------------------------------------------

async function readState() {
  return (await chrome.storage.local.get(STATE_KEY))[STATE_KEY] ?? INITIAL_STATE;
}

async function writeState(state) {
  await chrome.storage.local.set({ [STATE_KEY]: state });
}

async function agentInfo() {
  const manifest = chrome.runtime.getManifest();
  let instanceId = (await chrome.storage.local.get(INSTANCE_KEY))[INSTANCE_KEY];
  if (!instanceId) {
    instanceId = `ext-${uuidv4()}`;
    await chrome.storage.local.set({ [INSTANCE_KEY]: instanceId });
  }
  return {
    extInstanceId: instanceId,
    extVersion: manifest.version,
    browser: "chrome",
    os: navigator.userAgent.includes("Mac OS X") ? "macOS" : "unknown",
  };
}
