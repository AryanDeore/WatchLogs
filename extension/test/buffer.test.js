// The on-disk buffer's key schema and the two operations over it: rehydrate a
// capture session out of a storage snapshot, and turn an Ack into the exact set
// of keys to drop. Pure — the `chrome.storage.local` calls live in the worker
// and the page helper.

import test from "node:test";
import assert from "node:assert/strict";
import { initSession, apply, applyAck, buildFlush } from "../src/capture.js";
import {
  ackKey,
  eventKey,
  prunePlan,
  rehydrate,
  staleOpenViewIds,
  viewKey,
  writesFor,
} from "../src/buffer.js";

const T0 = Date.UTC(2026, 7, 29, 18, 0, 0);
const RUN = "run-a";

const agent = { extInstanceId: "ext-1", extVersion: "0.1.0", browser: "chrome", os: "macOS" };

const youtube = {
  service: "youtube",
  contentFormat: "standard",
  embedded: false,
  videoId: "dQw4w9WgXcQ",
  url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  durationSec: 213,
};

/** A frame that opened one View, played, and sampled twice. */
function frame() {
  const s = initSession(T0, { tabId: 41 });
  apply(s, { type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  apply(s, { type: "PLAY", at: T0 + 1000, pos: 0 });
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  apply(s, { type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: true });
  return s;
}

/** What the page helper would have written to disk for `s`, plus `extra`. */
function disk(s, extra = {}) {
  const items = { pairing: "unrelated-key-the-buffer-must-not-touch" };
  for (const id of s.order) Object.assign(items, writesFor(s.views[id], { runId: RUN }));
  return { ...items, ...extra };
}

test("one Event is one key, so an append and a prune never race each other", () => {
  const items = disk(frame());
  assert.deepEqual(Object.keys(items).sort(), [
    "pairing",
    viewKey("view-1"),
    eventKey("view-1", 1),
    eventKey("view-1", 2),
    eventKey("view-1", 3),
    eventKey("view-1", 4),
  ].sort());
  assert.equal(items[eventKey("view-1", 3)].type, "sample");
});

test("event keys sort in seq order as strings", () => {
  const keys = [9, 10, 100, 2].map((seq) => eventKey("v", seq));
  assert.deepEqual([...keys].sort(), [2, 9, 10, 100].map((seq) => eventKey("v", seq)));
});

test("the stored header carries the crash-recovery stamp and the run that made it", () => {
  const header = disk(frame())[viewKey("view-1")];
  assert.equal(header.runId, RUN);
  assert.equal(header.open, true);
  assert.equal(header.lastSeq, 4);
  assert.deepEqual(header.lastSample, { t: T0 + 11000, pos: 10 });
  assert.equal(header.startedAt, T0);
  assert.equal(header.tabId, 41);
});

test("writesFor only re-writes Events above the seq already on disk", () => {
  const s = frame();
  const writes = writesFor(s.views["view-1"], { runId: RUN, fromSeq: 3 });
  assert.deepEqual(Object.keys(writes).sort(), [viewKey("view-1"), eventKey("view-1", 4)].sort());
});

test("rehydrating a snapshot rebuilds a session that flushes the same body", () => {
  const s = frame();
  const direct = buildFlush(s, { flushId: "f-1", sentAt: T0 + 11000, agent });
  const revived = buildFlush(rehydrate(disk(s)), { flushId: "f-1", sentAt: T0 + 11000, agent });
  assert.deepEqual(revived, direct);
});

test("rehydrating puts Views in the order they started, whatever order the keys came in", () => {
  const s = frame();
  apply(s, { type: "CHANGE_VIDEO", at: T0 + 12000, pos: 11, viewId: "view-2", view: youtube });
  const items = disk(s);
  const shuffled = Object.fromEntries(Object.entries(items).reverse());
  assert.deepEqual(rehydrate(shuffled).order, ["view-1", "view-2"]);
});

test("a rehydrated session knows what the App has already Ack'd", () => {
  const items = disk(frame(), { [ackKey("view-1")]: { ackSeq: 3 } });
  const s = rehydrate(items);
  assert.equal(s.lastFlushAckSeq["view-1"], 3);
  assert.deepEqual(
    buildFlush(s, { flushId: "f-2", sentAt: T0, agent }).views[0].events.map((e) => e.seq),
    [4],
  );
});

test("an Ack drops every Event key at or below ackSeq and records the new high-water mark", () => {
  const items = disk(frame());
  const plan = prunePlan(items, { views: [{ viewId: "view-1", ackSeq: 3 }] });

  assert.deepEqual(plan.remove.sort(), [
    eventKey("view-1", 1),
    eventKey("view-1", 2),
    eventKey("view-1", 3),
  ].sort());
  assert.deepEqual(plan.set, { [ackKey("view-1")]: { ackSeq: 3 } });
});

test("an Ack for an open View keeps the header and the un-Ack'd Events", () => {
  const items = disk(frame());
  const plan = prunePlan(items, { views: [{ viewId: "view-1", ackSeq: 3 }] });
  assert.ok(!plan.remove.includes(viewKey("view-1")));
  assert.ok(!plan.remove.includes(eventKey("view-1", 4)));
});

test("a fully Ack'd closed View leaves the buffer entirely", () => {
  const s = frame();
  apply(s, { type: "VIEW_ENDED", at: T0 + 12000, pos: 11, reason: "nav" });
  const items = disk(s, { [ackKey("view-1")]: { ackSeq: 4 } });

  const plan = prunePlan(items, { views: [{ viewId: "view-1", ackSeq: 5 }] });
  assert.deepEqual(plan.set, {});
  assert.deepEqual(plan.remove.sort(), [
    viewKey("view-1"),
    ackKey("view-1"),
    ...[1, 2, 3, 4, 5].map((seq) => eventKey("view-1", seq)),
  ].sort());
});

test("a stale Ack never rewinds the high-water mark", () => {
  const items = disk(frame(), { [ackKey("view-1")]: { ackSeq: 4 } });
  const plan = prunePlan(items, { views: [{ viewId: "view-1", ackSeq: 2 }] });
  assert.deepEqual(plan.set, {});
  assert.deepEqual(plan.remove.sort(), [1, 2, 3, 4].map((seq) => eventKey("view-1", seq)).sort());
});

test("prune leaves keys that belong to other Views and to the rest of the extension", () => {
  const s = frame();
  apply(s, { type: "OPEN", at: T0 + 1000, viewId: "view-2", view: youtube });
  const plan = prunePlan(disk(s), { views: [{ viewId: "view-1", ackSeq: 4 }] });
  assert.ok(!plan.remove.some((key) => key.includes("view-2") || key === "pairing"));
});

test("Views left open by a previous browser run are the ones to recover", () => {
  const s = frame();
  apply(s, { type: "OPEN", at: T0 + 1000, viewId: "view-2", view: youtube });
  apply(s, { type: "VIEW_ENDED", at: T0 + 2000, pos: 1, reason: "nav" });
  const items = disk(s);

  assert.deepEqual(staleOpenViewIds(items, "run-b"), ["view-1"]);
  assert.deepEqual(staleOpenViewIds(items, RUN), []);
});

test("recovery round-trips: rehydrate, RESTART, write back, and the Flush says crash-recovered", () => {
  const items = disk(frame());
  const s = rehydrate(items);
  apply(s, { type: "RESTART", at: T0 + 900000 });
  const written = { ...items, ...writesFor(s.views["view-1"], { runId: "run-b", fromSeq: 4 }) };

  const body = buildFlush(rehydrate(written), { flushId: "f-3", sentAt: T0 + 900000, agent });
  assert.equal(body.views[0].open, false);
  assert.deepEqual(body.views[0].events.at(-1), {
    seq: 5,
    type: "viewEnded",
    t: T0 + 11000,
    pos: 10,
    reason: "crash-recovered",
  });
});

test("rehydrate ignores a fully Ack'd closed View that is mid-cleanup", () => {
  const s = frame();
  apply(s, { type: "VIEW_ENDED", at: T0 + 12000, pos: 11, reason: "nav" });
  const items = disk(s, { [ackKey("view-1")]: { ackSeq: 5 } });
  const revived = rehydrate(items);

  assert.equal(revived.flushedClosed["view-1"], true);
  assert.deepEqual(buildFlush(revived, { flushId: "f-4", sentAt: T0, agent }).views, []);
});

test("an Ack fold in memory and a prune on disk agree about what is left", () => {
  const s = frame();
  const ack = { views: [{ viewId: "view-1", ackSeq: 3 }] };
  const remaining = Object.keys(prunePlan(disk(s), ack).remove.reduce(
    (items, key) => (delete items[key], items),
    disk(s),
  )).filter((key) => key.startsWith("wl:evt:"));

  applyAck(s, ack);
  assert.deepEqual(remaining, s.views["view-1"].events.map((e) => eventKey("view-1", e.seq)));
});
