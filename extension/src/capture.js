// The capture-side seam: raw browser facts + Ack state in, Flush body out.
//
// A **Capture** is everything one browser context is holding for the App — its
// open Views, the Events recorded against them, and how far the App has
// acknowledged each one. The page helper drives a Capture from real player
// events; the background worker rebuilds one out of the on-disk buffer and
// calls `buildFlush` on it; the Node suite drives it directly.
//
// Lifted from the pure module in `prototypes/message-schema/index.html`
// (its `initSession` / `apply` / `buildFlush`) and kept pure — no DOM, no extension
// API. Four deliberate changes on the way over, all of them "stop simulating,
// start being told":
//
//   * the prototype's `advance(ms)` moved positions forward on a fake clock.
//     Here every action carries `at` (wall clock, epoch ms) and, where it makes
//     sense, `pos` (the player's own position) — the reducer is told, it never
//     guesses.
//   * the prototype's actions carried hard-coded fixtures (`OPEN` always meant
//     one particular YouTube video). Here the caller passes the View header and
//     mints the `viewId`, so the reducer stays free of both id generation and
//     site knowledge.
//   * `CRASH` is gone. A crash is by definition unobserved, so there is nothing
//     to record when it happens. `RESTART` survives as `END_OPEN_VIEWS`, which
//     takes the `reason`: the same "close what nobody watched end, stamped at
//     its last `sample`" move serves both a dead browser (`crash-recovered`)
//     and a tab that vanished (`tab-closed`).
//   * playback rate moved from the Capture onto the View, where the real
//     `playbackRate` lives.

export const SCHEMA_VERSION = 1;

/** The View header, exactly as schema v1 puts it on the wire. */
export const VIEW_FIELDS = [
  "viewId", "service", "contentFormat", "embedded", "videoId", "url", "title",
  "author", "durationSec", "metadataSource", "adapterId", "tabId",
  "startedAt", "open", "previousViewId",
];

/**
 * How many Events one Flush may carry. The App rejects a body over 1 MiB with
 * `413`, and an Event is well under 200 bytes, so this keeps a buffer that grew
 * over a long offline stretch draining across several Flushes instead of
 * building one body that can never be delivered.
 */
export const MAX_EVENTS_PER_FLUSH = 2000;

/**
 * The `HTMLMediaElement.readyState` at which the player holds data *beyond* the
 * current frame — the browser's own answer to "can playback actually continue?".
 */
export const HAVE_FUTURE_DATA = 3;

/**
 * Is this player actually moving, as opposed to merely un-paused?
 *
 * `paused` records only that something called `play()`. A player whose network
 * died mid-buffer — or that never loaded a byte — sits at `paused === false`
 * indefinitely while `currentTime` never advances, and reporting that as
 * playback banks Watched time for a video nobody watched. `readyState` is the
 * browser's own account of whether it has anything left to play, so it is what
 * decides.
 *
 * Pure, and takes the three fields rather than the element, so the reducer's
 * "no DOM" rule still holds.
 *
 * @param {{ paused: boolean, ended: boolean, readyState: number }} media
 */
export function isAdvancing({ paused, ended, readyState }) {
  return !paused && !ended && readyState >= HAVE_FUTURE_DATA;
}

/**
 * @typedef {{ extInstanceId: string, extVersion: string, browser: string, os: string }} Agent
 */

/**
 * An empty Capture.
 *
 * @param {number} now  epoch ms
 * @param {{ tabId?: number }} [options]
 */
export function initCapture(now, { tabId = 0 } = {}) {
  return {
    now,
    tabVisible: true,
    pip: false,
    tabId,
    views: {}, // viewId -> view
    activeViewId: null,
    order: [], // viewIds in creation order
    lastFlushAckSeq: {}, // viewId -> highest seq the App has Ack'd
    flushedClosed: {}, // viewId -> true once a closed View has been Ack'd whole
    lastSampleSnapshot: {}, // viewId -> {t, pos}, the crash-recovery stamp
  };
}

function newView(capture, viewId, header) {
  const view = {
    viewId,
    service: header.service,
    contentFormat: header.contentFormat ?? "standard",
    embedded: !!header.embedded,
    videoId: header.videoId,
    url: header.url,
    title: header.title ?? null,
    author: header.author ?? null,
    durationSec: header.durationSec ?? null,
    metadataSource: header.metadataSource ?? null,
    adapterId: header.adapterId ?? null,
    tabId: header.tabId ?? capture.tabId,
    startedAt: capture.now,
    open: true,
    previousViewId: header.previousViewId ?? null,
    events: [],
    _seq: 0,
    _playing: false,
    _pos: 0,
    _rate: 1,
    _lastSample: null,
  };
  capture.views[viewId] = view;
  capture.order.push(viewId);
  capture.activeViewId = viewId;
  capture.lastFlushAckSeq[viewId] ??= 0;
  emit(capture, viewId, "mediaFound", {});
  return view;
}

function emit(capture, viewId, type, extra) {
  const view = capture.views[viewId];
  if (!view) return;
  view._seq += 1;
  const event = { seq: view._seq, type, t: capture.now, pos: round3(view._pos) };
  Object.assign(event, extra);
  view.events.push(event);
  if (type === "sample") {
    // One object, two owners: the Capture keeps the prototype's lookup table and
    // the View keeps its own copy, so the buffer can persist it without the
    // whole Capture in hand.
    const snapshot = { t: capture.now, pos: round3(view._pos) };
    capture.lastSampleSnapshot[viewId] = snapshot;
    view._lastSample = snapshot;
  }
}

/** Media positions ride the wire as float seconds, 3 dp. */
function round3(n) {
  return n == null ? null : Math.round(n * 1000) / 1000;
}

/**
 * One raw browser fact -> a mutated Capture. Returns the Capture so callers can
 * chain; the mutation is the point (the page helper holds one Capture for the
 * life of the frame).
 *
 * Every action takes `at` (epoch ms) and may take `pos` (the player's position
 * in seconds) and `viewId` (which View it is about — the active one if absent).
 *
 * @param {ReturnType<typeof initCapture>} capture
 * @param {{ type: string, at?: number, pos?: number, viewId?: string, [k: string]: unknown }} action
 */
export function apply(capture, action) {
  if (Number.isFinite(action.at)) capture.now = action.at;

  switch (action.type) {
    case "OPEN":
      newView(capture, action.viewId, action.view);
      return capture;

    case "HIDE":
    case "SHOW": {
      // Visibility belongs to the frame, not to one player, so it is recorded
      // whether or not a View is open — a Capture that missed the `hidden`
      // would read the later `visible` as no transition at all.
      const visible = action.type === "SHOW";
      if (capture.tabVisible === visible) return capture;
      capture.tabVisible = visible;
      // One position can only belong to one player, so it moves the View the
      // caller named; the rest are stamped wherever they were last seen.
      const named = capture.views[action.viewId ?? ""];
      if (named && Number.isFinite(action.pos)) named._pos = action.pos;
      for (const viewId of capture.order) {
        if (capture.views[viewId].open) emit(capture, viewId, visible ? "visible" : "hidden", {});
      }
      return capture;
    }

    case "CHANGE_VIDEO": {
      // `action.viewId` is the *next* View's id, so the one to close is named by
      // `fromViewId` — or, when the caller only tracks one player, the active one.
      const previous = capture.views[action.fromViewId ?? capture.activeViewId ?? ""] ?? null;
      if (previous?.open) {
        if (Number.isFinite(action.pos)) previous._pos = action.pos;
        previous._playing = false;
        emit(capture, previous.viewId, "viewEnded", { reason: "video-changed" });
        previous.open = false;
      }
      newView(capture, action.viewId, { ...action.view, previousViewId: previous?.viewId ?? null });
      return capture;
    }

    case "END_OPEN_VIEWS":
      // Views still marked open that nothing is left to close them: nothing
      // observed how they ended, so the last `sample` is the last moment we can
      // honestly claim.
      for (const viewId of capture.order) {
        const view = capture.views[viewId];
        if (!view.open) continue;
        const sample = capture.lastSampleSnapshot[viewId] ??
          view._lastSample ?? { t: view.startedAt, pos: 0 };
        view._playing = false;
        view._seq += 1;
        view.events.push({
          seq: view._seq,
          type: "viewEnded",
          t: sample.t,
          pos: round3(sample.pos),
          reason: action.reason,
        });
        view.open = false;
      }
      capture.activeViewId = null;
      return capture;
  }

  const view = capture.views[action.viewId ?? capture.activeViewId ?? ""] ?? null;
  if (!view || !view.open) return capture;
  if (Number.isFinite(action.pos)) view._pos = action.pos;

  switch (action.type) {
    case "PLAY":
      if (!view._playing) {
        view._playing = true;
        emit(capture, view.viewId, "play", {});
      }
      break;
    case "PAUSE":
      if (view._playing) {
        view._playing = false;
        emit(capture, view.viewId, "pause", {});
      }
      break;

    case "SEEKED":
      view._pos = action.to;
      emit(capture, view.viewId, "seeked", { from: round3(action.from), to: round3(action.to) });
      break;
    case "RATE":
      if (view._rate !== action.rate) {
        view._rate = action.rate;
        emit(capture, view.viewId, "ratechange", { rate: action.rate });
      }
      break;

    case "PIP_ENTER":
      if (!capture.pip) {
        capture.pip = true;
        emit(capture, view.viewId, "pipEnter", {});
      }
      break;
    case "PIP_LEAVE":
      if (capture.pip) {
        capture.pip = false;
        emit(capture, view.viewId, "pipLeave", {});
      }
      break;

    case "META":
      Object.assign(view, action.changed);
      if (action.metadataSource) view.metadataSource = action.metadataSource;
      if (action.adapterId !== undefined) view.adapterId = action.adapterId;
      emit(capture, view.viewId, "metadataChange", { changed: action.changed });
      break;

    case "SAMPLE":
      emit(capture, view.viewId, "sample", { playing: !!action.playing, visible: !!action.visible });
      break;

    case "MEDIA_ENDED":
      // Natural end of the media, not of the View — a replay keeps the View.
      view._playing = false;
      emit(capture, view.viewId, "ended", {});
      break;

    case "VIEW_ENDED":
      view._playing = false;
      emit(capture, view.viewId, "viewEnded", { reason: action.reason });
      view.open = false;
      if (capture.activeViewId === view.viewId) capture.activeViewId = null;
      break;
  }
  return capture;
}

/**
 * The `POST /v1/flush` body for what the Capture still owes the App, up to
 * `maxEvents` Events. Views ride in the order they started, so a truncated
 * batch is simply continued by the next Flush.
 *
 * @param {ReturnType<typeof initCapture>} capture
 * @param {{ flushId: string, sentAt: number, agent: Agent, maxEvents?: number }} params
 */
export function buildFlush(capture, { flushId, sentAt, agent, maxEvents = MAX_EVENTS_PER_FLUSH }) {
  const views = [];
  let budget = maxEvents;

  for (const viewId of capture.order) {
    if (budget <= 0) break;
    const view = capture.views[viewId];
    const since = capture.lastFlushAckSeq[viewId] || 0;
    const fresh = view.events.filter((event) => event.seq > since).slice(0, budget);
    const closedAlreadyFlushed = !view.open && capture.flushedClosed[viewId];
    if (fresh.length === 0 && view.open) continue; // nothing new on an open View
    if (closedAlreadyFlushed) continue; // closed View already delivered
    budget -= fresh.length;

    const header = {};
    for (const field of VIEW_FIELDS) header[field] = view[field];
    // `open` mirrors "this batch does not carry the View's viewEnded", which a
    // truncated batch does not, however closed the View itself is.
    header.open = !fresh.some((event) => event.type === "viewEnded");
    header.events = fresh;
    views.push(header);
  }

  return { schemaVersion: SCHEMA_VERSION, flushId, sentAt, agent, views };
}
