// The capture-side seam: raw browser facts + Ack state in, Flush body out.
//
// Lifted from the pure module in `prototypes/message-schema/index.html`
// (`initSession` / `apply` / `buildFlush`) and kept pure — no DOM, no
// extension API. The page helper drives it from real player events; the background
// worker rehydrates a session out of the on-disk buffer and calls `buildFlush`
// on it; the Node suite drives it directly.
//
// Three deliberate changes on the way over from the prototype, all of them
// "stop simulating, start being told":
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
//     to record when it happens; only `RESTART` — closing whatever was still
//     open, stamped at its last `sample` — survives into the real thing.

export const SCHEMA_VERSION = 1;

/**
 * @typedef {{ extInstanceId: string, extVersion: string, browser: string, os: string }} Agent
 */

/**
 * A capture session: every View this page helper (or, when rehydrated, this
 * whole browser) is holding, plus what the App has already Ack'd.
 *
 * @param {number} now  epoch ms
 * @param {{ tabId?: number }} [options]
 */
export function initSession(now, { tabId = 0 } = {}) {
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

function newView(s, viewId, opts) {
  const v = {
    viewId,
    service: opts.service,
    contentFormat: opts.contentFormat ?? "standard",
    embedded: !!opts.embedded,
    videoId: opts.videoId,
    url: opts.url,
    title: opts.title ?? null,
    author: opts.author ?? null,
    artworkUrl: opts.artworkUrl ?? null,
    durationSec: opts.durationSec ?? null,
    metadataSource: opts.metadataSource ?? null,
    adapterId: opts.adapterId ?? null,
    tabId: opts.tabId ?? s.tabId,
    startedAt: s.now,
    open: true,
    previousViewId: opts.previousViewId ?? null,
    events: [],
    _seq: 0,
    _playing: false,
    _pos: 0,
    _rate: 1,
    _lastSample: null,
  };
  s.views[viewId] = v;
  s.order.push(viewId);
  s.activeViewId = viewId;
  s.lastFlushAckSeq[viewId] ??= 0;
  emit(s, viewId, "mediaFound", {});
  return v;
}

function emit(s, viewId, type, extra) {
  const v = s.views[viewId];
  if (!v) return;
  v._seq += 1;
  const ev = { seq: v._seq, type, t: s.now, pos: round3(v._pos) };
  Object.assign(ev, extra);
  v.events.push(ev);
  if (type === "sample") {
    // One object, two owners: the session keeps the prototype's lookup table and
    // the View keeps its own copy so the buffer can persist it without the
    // session in hand.
    const snapshot = { t: s.now, pos: round3(v._pos) };
    s.lastSampleSnapshot[viewId] = snapshot;
    v._lastSample = snapshot;
  }
}

export function round3(n) {
  return n == null ? null : Math.round(n * 1000) / 1000;
}

/**
 * One raw browser fact -> a mutated session. Returns the session so callers can
 * chain; the mutation is the point (the page helper holds one session for the
 * life of the frame).
 *
 * Every action takes `at` (epoch ms) and may take `pos` (the player's position
 * in seconds) and `viewId` (which View it is about — the active one if absent).
 *
 * @param {ReturnType<typeof initSession>} s
 * @param {{ type: string, at?: number, pos?: number, viewId?: string, [k: string]: unknown }} action
 */
export function apply(s, action) {
  if (Number.isFinite(action.at)) s.now = action.at;

  if (action.type === "OPEN") {
    newView(s, action.viewId, action.view);
    return s;
  }

  if (action.type === "CHANGE_VIDEO") {
    // `action.viewId` is the *next* View's id, so the one to close is named by
    // `fromViewId` — or, when the caller only tracks one player, the active one.
    const previous = s.views[action.fromViewId ?? s.activeViewId ?? ""] ?? null;
    if (previous?.open) {
      if (Number.isFinite(action.pos)) previous._pos = action.pos;
      previous._playing = false;
      emit(s, previous.viewId, "viewEnded", { reason: "video-changed" });
      previous.open = false;
    }
    newView(s, action.viewId, { ...action.view, previousViewId: previous?.viewId ?? null });
    return s;
  }

  if (action.type === "RESTART") {
    // Fresh browser run with Views still marked open: nothing observed how they
    // ended, so the last `sample` is the last moment we can honestly claim.
    for (const id of s.order) {
      const v = s.views[id];
      if (!v.open) continue;
      const snap = s.lastSampleSnapshot[id] ?? v._lastSample ?? { t: v.startedAt, pos: 0 };
      v._playing = false;
      v._seq += 1;
      v.events.push({
        seq: v._seq,
        type: "viewEnded",
        t: snap.t,
        pos: round3(snap.pos),
        reason: "crash-recovered",
      });
      v.open = false;
    }
    s.activeViewId = null;
    return s;
  }

  const a = s.views[action.viewId ?? s.activeViewId ?? ""] ?? null;
  if (!a || !a.open) return s;
  if (Number.isFinite(action.pos)) a._pos = action.pos;

  switch (action.type) {
    case "PLAY":
      if (!a._playing) {
        a._playing = true;
        emit(s, a.viewId, "play", {});
      }
      break;
    case "PAUSE":
      if (a._playing) {
        a._playing = false;
        emit(s, a.viewId, "pause", {});
      }
      break;

    case "SEEKED":
      a._pos = action.to;
      emit(s, a.viewId, "seeked", { from: round3(action.from), to: round3(action.to) });
      break;
    case "RATE":
      if (a._rate !== action.rate) {
        a._rate = action.rate;
        emit(s, a.viewId, "ratechange", { rate: action.rate });
      }
      break;

    case "HIDE":
    case "SHOW": {
      // Visibility belongs to the frame, not to one player: every open View in
      // this session hears about it.
      const visible = action.type === "SHOW";
      if (s.tabVisible === visible) break;
      s.tabVisible = visible;
      for (const id of s.order) {
        if (s.views[id].open) emit(s, id, visible ? "visible" : "hidden", {});
      }
      break;
    }

    case "PIP_ENTER":
      if (!s.pip) {
        s.pip = true;
        emit(s, a.viewId, "pipEnter", {});
      }
      break;
    case "PIP_LEAVE":
      if (s.pip) {
        s.pip = false;
        emit(s, a.viewId, "pipLeave", {});
      }
      break;

    case "META":
      Object.assign(a, action.changed);
      if (action.metadataSource) a.metadataSource = action.metadataSource;
      if (action.adapterId !== undefined) a.adapterId = action.adapterId;
      emit(s, a.viewId, "metadataChange", { changed: action.changed });
      break;

    case "SAMPLE":
      emit(s, a.viewId, "sample", { playing: !!action.playing, visible: !!action.visible });
      break;

    case "MEDIA_ENDED":
      // Natural end of the media, not of the View — a replay keeps the View.
      a._playing = false;
      emit(s, a.viewId, "ended", {});
      break;

    case "VIEW_ENDED":
      a._playing = false;
      emit(s, a.viewId, "viewEnded", { reason: action.reason });
      a.open = false;
      if (s.activeViewId === a.viewId) s.activeViewId = null;
      break;
  }
  return s;
}

/**
 * Fold an Ack back into the session: everything at or below `ackSeq` is the
 * App's problem now, so it leaves the buffer.
 *
 * @param {ReturnType<typeof initSession>} s
 * @param {{ views?: Array<{ viewId: string, ackSeq: number }> }} ack
 */
export function applyAck(s, ack) {
  for (const { viewId, ackSeq } of ack?.views ?? []) {
    const highest = Math.max(s.lastFlushAckSeq[viewId] ?? 0, ackSeq);
    s.lastFlushAckSeq[viewId] = highest;
    const v = s.views[viewId];
    if (!v) continue;
    v.events = v.events.filter((e) => e.seq > highest);
    if (!v.open && highest >= v._seq) s.flushedClosed[viewId] = true;
  }
  return s;
}

/**
 * The `POST /v1/flush` body for everything the session still owes the App.
 *
 * @param {ReturnType<typeof initSession>} s
 * @param {{ flushId: string, sentAt: number, agent: Agent }} params
 */
export function buildFlush(s, { flushId, sentAt, agent }) {
  const views = [];
  for (const id of s.order) {
    const v = s.views[id];
    const since = s.lastFlushAckSeq[id] || 0;
    const fresh = v.events.filter((e) => e.seq > since);
    const closedAlreadyFlushed = !v.open && s.flushedClosed[id];
    if (fresh.length === 0 && v.open) continue; // nothing new on an open View
    if (closedAlreadyFlushed) continue; // closed View already delivered
    views.push({
      viewId: v.viewId,
      service: v.service,
      contentFormat: v.contentFormat,
      embedded: v.embedded,
      videoId: v.videoId,
      url: v.url,
      title: v.title,
      author: v.author,
      artworkUrl: v.artworkUrl,
      durationSec: v.durationSec,
      metadataSource: v.metadataSource,
      adapterId: v.adapterId,
      tabId: v.tabId,
      startedAt: v.startedAt,
      open: v.open,
      previousViewId: v.previousViewId,
      events: fresh,
    });
  }
  return { schemaVersion: SCHEMA_VERSION, flushId, sentAt, agent, views };
}
