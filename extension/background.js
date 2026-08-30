// Service worker: hold the pairing string, post an empty-`views` heartbeat on a
// timer, process the Ack, and drop to a "re-pair" state on 401 (issue #26).

import { parsePairingString, baseUrl } from "./src/pairing.js";
import { buildHeartbeat, interpretFlushResponse } from "./src/flush.js";
import { INITIAL_STATE, reduce } from "./src/state.js";

const PAIRING_KEY = "pairing";
const STATE_KEY = "connectionState";
const INSTANCE_KEY = "extInstanceId";
const HEARTBEAT_ALARM = "watchlogs-heartbeat";
const HEARTBEAT_MS = 5000;

// --- Timers -----------------------------------------------------------------

chrome.runtime.onInstalled.addListener(() => {
  ensureAlarm();
  void flushHeartbeat();
});

chrome.runtime.onStartup.addListener(() => {
  ensureAlarm();
  void flushHeartbeat();
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === HEARTBEAT_ALARM) void flushHeartbeat();
});

// Fast cadence while the worker is alive; the alarm is the >=1-min backstop.
setInterval(() => {
  void flushHeartbeat();
}, HEARTBEAT_MS);

function ensureAlarm() {
  chrome.alarms.create(HEARTBEAT_ALARM, { periodInMinutes: 1, delayInMinutes: 0 });
}

// --- Heartbeat ------------------------------------------------------------------

async function flushHeartbeat() {
  const raw = (await chrome.storage.local.get(PAIRING_KEY))[PAIRING_KEY];
  if (!raw) {
    await writeState({ status: "needs-pairing" });
    return;
  }

  let pairing;
  try {
    pairing = parsePairingString(raw);
  } catch {
    await writeState({ status: "needs-pairing", reason: "bad-pairing-string", at: Date.now() });
    return;
  }

  const flushId = crypto.randomUUID();
  const body = buildHeartbeat({
    flushId,
    sentAt: Date.now(),
    agent: await agentInfo(),
  });

  let status = 0;
  let payload = null;
  try {
    const response = await fetch(`${baseUrl(pairing)}/v1/flush`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${pairing.token}`,
      },
      body: JSON.stringify(body),
    });
    status = response.status;
    payload = await response.json().catch(() => null);
  } catch {
    await writeState(reduce(await readState(), { outcome: "retry" }, Date.now()));
    return;
  }

  const decision = interpretFlushResponse(status, payload);
  if (decision.outcome === "re-pair") {
    await chrome.alarms.clear(HEARTBEAT_ALARM);
  }
  await writeState(reduce(await readState(), decision, Date.now()));
}

// --- Pairing (called from the options page) -----------------------------------

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "pair") {
    void pair(message.pairingString).then(sendResponse);
    return true; // async response
  }
  if (message?.type === "getState") {
    void readState().then(sendResponse);
    return true;
  }
  return false;
});

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
  ensureAlarm();
  await flushHeartbeat();
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
    instanceId = `ext-${crypto.randomUUID()}`;
    await chrome.storage.local.set({ [INSTANCE_KEY]: instanceId });
  }
  return {
    extInstanceId: instanceId,
    extVersion: manifest.version,
    browser: "chrome",
    os: navigator.userAgent.includes("Mac OS X") ? "macOS" : "unknown",
  };
}
