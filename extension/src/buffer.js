// The on-disk buffer's key schema, and the two pure operations over it: rebuild
// a Capture out of a storage snapshot, and turn an Ack into the exact set of
// keys to drop.
//
// The layout exists to make concurrent writers safe. The page helper appends
// and the background worker prunes, in different processes, with no lock
// between them — so nothing is ever read-modify-written by both. Each key has
// exactly one writer:
//
//   wl:view:<viewId>            the View header  — written by the owning frame
//   wl:evt:<viewId>:<seq>       one Event        — written by the owning frame
//   wl:ack:<viewId>             the high-water mark — written by the worker
//
// The worker deletes frame-owned keys in two cases, both of them keys the frame
// is finished with: an Event at or below the Ack'd `seq` (a frame only ever
// writes a given `seq` once, and only ever counts up), and the header of a View
// that is closed and fully Ack'd. An Event is a whole key of its own, so an
// append landing during a prune can't be clobbered by it.

import { VIEW_FIELDS } from "./capture.js";

const VIEW_PREFIX = "wl:view:";
const EVENT_PREFIX = "wl:evt:";
const ACK_PREFIX = "wl:ack:";

/** Wide enough that string order and numeric order are the same order. */
const SEQ_DIGITS = 9;

/** The key holding one View's header. Written by the frame that owns the View. */
export function viewKey(viewId) {
  return `${VIEW_PREFIX}${viewId}`;
}

/** The key holding one Event. Written by the frame, deleted by the worker on the Ack. */
export function eventKey(viewId, seq) {
  return `${EVENT_PREFIX}${viewId}:${String(seq).padStart(SEQ_DIGITS, "0")}`;
}

/** The key holding one View's Ack high-water mark. Written by the worker alone. */
export function ackKey(viewId) {
  return `${ACK_PREFIX}${viewId}`;
}

/**
 * The storage writes that bring one View up to date: its header, plus every
 * Event above what is already on disk.
 *
 * @param {object} view  a View out of a Capture (see `capture.js`)
 * @param {{ runId?: string, fromSeq?: number }} [options]
 *   `runId` stamps which browser run owns the View — a View still open under an
 *   older run is one the browser died on. Defaults to the stamp it already has.
 * @returns {Record<string, unknown>} storage items to `set`
 */
export function writesFor(view, { runId, fromSeq = 0 } = {}) {
  const header = {};
  for (const field of VIEW_FIELDS) header[field] = view[field];
  header.runId = runId ?? view._runId ?? null;
  header.lastSeq = view._seq;
  header.lastSample = view._lastSample ?? null;

  const writes = { [viewKey(view.viewId)]: header };
  for (const event of view.events) {
    if (event.seq > fromSeq) writes[eventKey(view.viewId, event.seq)] = event;
  }
  return writes;
}

/**
 * Rebuild a Capture from a `chrome.storage.local` snapshot. Keys that aren't the
 * buffer's (the pairing string, the connection state) are ignored.
 *
 * @param {Record<string, any>} items
 * @param {{ now?: number }} [options]
 */
export function rehydrate(items, { now = 0 } = {}) {
  const headers = [];
  const eventsByView = new Map();
  const ackByView = new Map();

  for (const [key, value] of Object.entries(items)) {
    if (key.startsWith(VIEW_PREFIX)) {
      headers.push(value);
    } else if (key.startsWith(EVENT_PREFIX)) {
      const viewId = key.slice(EVENT_PREFIX.length, key.lastIndexOf(":"));
      if (!eventsByView.has(viewId)) eventsByView.set(viewId, []);
      eventsByView.get(viewId).push(value);
    } else if (key.startsWith(ACK_PREFIX)) {
      ackByView.set(key.slice(ACK_PREFIX.length), value?.ackSeq ?? 0);
    }
  }

  const capture = {
    now,
    tabVisible: true,
    pip: false,
    tabId: 0,
    views: {},
    activeViewId: null,
    order: [],
    lastFlushAckSeq: {},
    flushedClosed: {},
    lastSampleSnapshot: {},
  };

  // Creation order, reconstructed: the keys come back in whatever order storage
  // felt like, but `startedAt` is on every header.
  headers.sort((a, b) => a.startedAt - b.startedAt || String(a.viewId).localeCompare(b.viewId));


  for (const header of headers) {
    const events = (eventsByView.get(header.viewId) ?? []).sort((a, b) => a.seq - b.seq);
    const view = {};
    for (const field of VIEW_FIELDS) view[field] = header[field];
    view.events = events;
    view._seq = header.lastSeq ?? events.at(-1)?.seq ?? 0;
    view._playing = false;
    view._pos = events.at(-1)?.pos ?? header.lastSample?.pos ?? 0;
    view._rate = 1;
    view._lastSample = header.lastSample ?? null;
    view._runId = header.runId ?? null;

    const ackSeq = ackByView.get(header.viewId) ?? 0;
    capture.views[header.viewId] = view;
    capture.order.push(header.viewId);
    capture.lastFlushAckSeq[header.viewId] = ackSeq;
    if (header.lastSample) capture.lastSampleSnapshot[header.viewId] = header.lastSample;
    if (!view.open && ackSeq >= view._seq) capture.flushedClosed[header.viewId] = true;
  }

  return capture;
}

/** The viewIds a previous browser run left open — the crash-recovery candidates. */
export function staleOpenViewIds(items, runId) {
  return Object.entries(items)
    .filter(([key, header]) => key.startsWith(VIEW_PREFIX) && header?.open && header?.runId !== runId)
    .map(([, header]) => header.viewId);
}

/**
 * What to change in storage once the App has Ack'd: every Event at or below
 * `ackSeq` goes, and a View that is closed and fully Ack'd goes with it.
 *
 * @param {Record<string, any>} items  the same snapshot the Flush was built from
 * @param {{ views?: Array<{ viewId: string, ackSeq: number }> }} ack
 * @returns {{ remove: string[], set: Record<string, unknown> }}
 */
export function prunePlan(items, ack) {
  const remove = [];
  const set = {};

  for (const { viewId, ackSeq } of ack?.views ?? []) {
    const previous = items[ackKey(viewId)]?.ackSeq ?? 0;
    const highest = Math.max(previous, ackSeq);
    const header = items[viewKey(viewId)];
    // No header means the View was already cleaned up and this is a duplicate
    // Ack: take the whole viewId with us rather than leaving an orphan key.
    const done = !header || (!header.open && highest >= header.lastSeq);

    const ownPrefix = `${EVENT_PREFIX}${viewId}:`;
    for (const key of Object.keys(items)) {
      if (!key.startsWith(ownPrefix)) continue;
      if (done || items[key].seq <= highest) remove.push(key);
    }

    if (done) {
      if (header) remove.push(viewKey(viewId));
      if (items[ackKey(viewId)] !== undefined) remove.push(ackKey(viewId));
    } else if (highest !== previous) {
      set[ackKey(viewId)] = { ackSeq: highest };
    }
  }

  return { remove, set };
}
