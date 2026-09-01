// One scripted browser run, driven through the same three moving parts the real
// extension has: a page helper that appends to a buffer, a worker that builds
// the Flush and prunes on the Ack, and an App that answers like the real one.
//
// The pieces are the real modules; only `chrome.storage.local` and the network
// are stand-ins.

import test from "node:test";
import assert from "node:assert/strict";
import { apply, buildFlush, initCapture } from "../src/capture.js";
import { prunePlan, rehydrate, staleOpenViewIds, viewKey, writesFor } from "../src/buffer.js";

const T0 = Date.UTC(2026, 7, 29, 18, 0, 0);
const agent = { extInstanceId: "ext-1", extVersion: "0.1.0", browser: "chrome", os: "macOS" };
const youtube = {
  service: "youtube.com",
  contentFormat: "standard",
  embedded: false,
  videoId: "sha1:9c2f",
  url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  durationSec: 213,
};

/** `chrome.storage.local`, minus the promises. */
function storage() {
  const items = {};
  return {
    items,
    set: (writes) => Object.assign(items, structuredClone(writes)),
    remove: (keys) => keys.forEach((key) => delete items[key]),
    snapshot: () => structuredClone(items),
  };
}

/** A page helper: holds a live session and writes through to the buffer. */
function pageHelper(disk, runId, { tabId = 41 } = {}) {
  const session = initCapture(T0, { tabId });
  const persisted = new Map();
  return {
    session,
    act(action) {
      apply(session, action);
      const writes = {};
      for (const viewId of session.order) {
        const view = session.views[viewId];
        if (persisted.get(viewId) === view._seq) continue;
        Object.assign(writes, writesFor(view, { runId, fromSeq: persisted.get(viewId) ?? 0 }));
        persisted.set(viewId, view._seq);
      }
      disk.set(writes);
    },
  };
}

/** The worker: rehydrate, build, post, prune. Returns the body it sent. */
function flushOnce(disk, app, { flushId, sentAt }) {
  const items = disk.snapshot();
  const body = buildFlush(rehydrate(items, { now: sentAt }), { flushId, sentAt, agent });
  const ack = app.receive(body);
  if (ack) {
    const plan = prunePlan(items, ack);
    disk.set(plan.set);
    disk.remove(plan.remove);
  }
  return body;
}

/** The App: appends to a log, Acks the highest seq it holds per View. */
function fakeApp() {
  const log = new Map(); // viewId -> Map(seq -> event)
  const acks = new Map(); // flushId -> ack
  return {
    log,
    receive(body) {
      if (acks.has(body.flushId)) return acks.get(body.flushId); // replayed
      for (const view of body.views) {
        if (!log.has(view.viewId)) log.set(view.viewId, new Map());
        for (const event of view.events) log.get(view.viewId).set(event.seq, event);
      }
      const ack = {
        flushId: body.flushId,
        accepted: true,
        views: body.views.map((view) => ({
          viewId: view.viewId,
          ackSeq: Math.max(...log.get(view.viewId).keys()),
        })),
        serverTime: body.sentAt + 3,
      };
      acks.set(body.flushId, ack);
      return ack;
    },
    events(viewId) {
      return [...(log.get(viewId)?.values() ?? [])].sort((a, b) => a.seq - b.seq);
    },
  };
}

test("a watched minute arrives once, in order, and leaves the buffer empty", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  for (let beat = 1; beat <= 12; beat += 1) {
    const at = T0 + 1000 + beat * 5000;
    frame.act({ type: "SAMPLE", at, pos: beat * 5, playing: true, visible: true });
    flushOnce(disk, app, { flushId: `f-${beat}`, sentAt: at });
  }

  const seqs = app.events("view-1").map((e) => e.seq);
  assert.deepEqual(seqs, Array.from({ length: 14 }, (_, i) => i + 1));
  assert.equal(app.events("view-1").at(-1).t, T0 + 61000);
  // Everything Ack'd: the buffer holds one header and one high-water mark, no Events.
  assert.deepEqual(
    Object.keys(disk.items).filter((key) => key.startsWith("wl:evt:")),
    [],
  );
});

test("a View reappears in a later Flush only with higher-seq Events", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 1000 });

  assert.deepEqual(flushOnce(disk, app, { flushId: "f-2", sentAt: T0 + 2000 }).views, []);

  frame.act({ type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  const third = flushOnce(disk, app, { flushId: "f-3", sentAt: T0 + 6000 });
  assert.deepEqual(third.views[0].events.map((e) => e.seq), [3]);
});

test("a lost Ack costs a duplicate, not a gap", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });

  // The App answers, but the response never reaches us: no prune happens.
  const items = disk.snapshot();
  const lost = buildFlush(rehydrate(items), { flushId: "f-1", sentAt: T0 + 1000, agent });
  app.receive(lost);

  frame.act({ type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  // The retry reuses the flushId, so the App replays its Ack instead of storing twice.
  const retry = flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 6000 });
  assert.deepEqual(retry.views[0].events.map((e) => e.seq), [1, 2, 3]);
  assert.deepEqual(app.events("view-1").map((e) => e.seq), [1, 2]);

  const next = flushOnce(disk, app, { flushId: "f-2", sentAt: T0 + 11000 });
  assert.deepEqual(next.views[0].events.map((e) => e.seq), [3]);
  assert.deepEqual(app.events("view-1").map((e) => e.seq), [1, 2, 3]);
});

test("an autoplay chain is two linked Views, and the first one stops repeating", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  frame.act({ type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 6000 });

  frame.act({
    type: "CHANGE_VIDEO",
    at: T0 + 8000,
    pos: 7,
    fromViewId: "view-1",
    viewId: "view-2",
    view: { ...youtube, videoId: "sha1:kJQP" },
  });
  const handover = flushOnce(disk, app, { flushId: "f-2", sentAt: T0 + 8000 });

  assert.deepEqual(handover.views.map((v) => [v.viewId, v.open]), [["view-1", false], ["view-2", true]]);
  assert.equal(handover.views[1].previousViewId, "view-1");
  assert.equal(app.events("view-1").at(-1).reason, "video-changed");

  frame.act({ type: "PLAY", at: T0 + 9000, pos: 0 });
  const after = flushOnce(disk, app, { flushId: "f-3", sentAt: T0 + 9000 });
  assert.deepEqual(after.views.map((v) => v.viewId), ["view-2"]);
  // The closed View is gone from the buffer entirely.
  assert.ok(!Object.keys(disk.items).some((key) => key.includes("view-1")));
});

test("killing the browser mid-play re-Flushes the View at its last sample", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  frame.act({ type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 6000 });
  frame.act({ type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: true });
  // The browser dies here: the last sample never made it out, and nothing
  // observed the end.

  // Next launch: no session storage, so this is a fresh run.
  const nextRun = "run-b";
  const items = disk.snapshot();
  const stale = staleOpenViewIds(items, nextRun);
  assert.deepEqual(stale, ["view-1"]);

  const recovery = rehydrate(items, { now: T0 + 900000 });
  recovery.order = recovery.order.filter((id) => stale.includes(id));
  apply(recovery, { type: "END_OPEN_VIEWS", reason: "crash-recovered" });
  const writes = {};
  for (const viewId of recovery.order) {
    Object.assign(writes, writesFor(recovery.views[viewId], { fromSeq: items[viewKey(viewId)].lastSeq }));
  }
  disk.set(writes);

  const body = flushOnce(disk, app, { flushId: "f-2", sentAt: T0 + 900000 });
  assert.equal(body.views[0].open, false);
  assert.deepEqual(body.views[0].events.map((e) => [e.seq, e.type]), [[4, "sample"], [5, "viewEnded"]]);
  assert.deepEqual(body.views[0].events.at(-1), {
    seq: 5,
    type: "viewEnded",
    t: T0 + 11000,
    pos: 10,
    reason: "crash-recovered",
  });

  // A second launch has nothing left to recover.
  assert.deepEqual(staleOpenViewIds(disk.snapshot(), "run-c"), []);
});

test("a hidden tab keeps reporting, and the wire never says background", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");

  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  frame.act({ type: "HIDE", at: T0 + 2000, pos: 1 });
  frame.act({ type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: false });
  frame.act({ type: "PIP_ENTER", at: T0 + 7000, pos: 6 });
  frame.act({ type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: false });

  const body = flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 11000 });
  assert.deepEqual(
    body.views[0].events.map((e) => e.type),
    ["mediaFound", "play", "hidden", "sample", "pipEnter", "sample"],
  );
  assert.equal(body.views[0].events.at(-1).visible, false);
  assert.ok(!JSON.stringify(body).includes("background"));
});

test("two tabs on the same video are two Views that never share a seq", () => {
  const disk = storage();
  const app = fakeApp();
  const left = pageHelper(disk, "run-a", { tabId: 41 });
  const right = pageHelper(disk, "run-a", { tabId: 42 });

  left.act({ type: "OPEN", at: T0, viewId: "view-l", view: youtube });
  right.act({ type: "OPEN", at: T0 + 100, viewId: "view-r", view: youtube });
  left.act({ type: "PLAY", at: T0 + 1000, pos: 0 });
  right.act({ type: "PLAY", at: T0 + 1100, pos: 0 });

  const body = flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 2000 });
  assert.deepEqual(body.views.map((v) => [v.viewId, v.tabId]), [["view-l", 41], ["view-r", 42]]);
  assert.deepEqual(body.views.map((v) => v.events.map((e) => e.seq)), [[1, 2], [1, 2]]);
});

test("the wire carries every field schema v1 makes required", () => {
  const disk = storage();
  const app = fakeApp();
  const frame = pageHelper(disk, "run-a");
  frame.act({ type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  frame.act({ type: "SEEKED", at: T0 + 2000, from: 1, to: 45 });
  frame.act({ type: "RATE", at: T0 + 3000, pos: 45, rate: 2 });
  frame.act({ type: "VIEW_ENDED", at: T0 + 4000, pos: 46, reason: "tab-closed" });

  const body = flushOnce(disk, app, { flushId: "f-1", sentAt: T0 + 4000 });
  for (const field of ["schemaVersion", "flushId", "sentAt", "agent", "views"]) {
    assert.ok(body[field] !== undefined, `envelope.${field}`);
  }
  for (const field of ["viewId", "service", "contentFormat", "embedded", "videoId", "url",
    "tabId", "startedAt", "open", "events"]) {
    assert.ok(body.views[0][field] !== undefined, `view.${field}`);
  }
  for (const event of body.views[0].events) {
    assert.equal(typeof event.seq, "number");
    assert.equal(typeof event.type, "string");
    assert.equal(typeof event.t, "number");
    assert.ok(Number.isInteger(event.t));
  }
});
