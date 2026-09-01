// The seam this slice is built around: raw browser facts + Ack state in, Flush
// body out. Everything here is pure — the same module the page helper and the
// background worker both import (`src/capture.js`).

import test from "node:test";
import assert from "node:assert/strict";
import { SCHEMA_VERSION, initCapture, apply, buildFlush } from "../src/capture.js";

const T0 = Date.UTC(2026, 7, 29, 18, 0, 0);

const agent = {
  extInstanceId: "ext-1",
  extVersion: "0.1.0",
  browser: "chrome",
  os: "macOS",
};

const youtube = {
  service: "youtube",
  contentFormat: "standard",
  embedded: false,
  videoId: "dQw4w9WgXcQ",
  url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  durationSec: 213,
};

/** A session with one open, playing View. */
function playing({ tabId = 41 } = {}) {
  const s = initCapture(T0, { tabId });
  apply(s, { type: "OPEN", at: T0, viewId: "view-1", view: youtube });
  apply(s, { type: "PLAY", at: T0 + 1000, pos: 0 });
  return s;
}

const types = (s, viewId) => s.views[viewId].events.map((e) => e.type);
const flush = (s, at = T0) => buildFlush(s, { flushId: "flush-1", sentAt: at, agent });

test("opening a View mints seq 1 as mediaFound and stamps the wall clock", () => {
  const s = playing();
  const view = s.views["view-1"];
  assert.equal(view.startedAt, T0);
  assert.equal(view.tabId, 41);
  assert.equal(view.open, true);
  assert.equal(view.previousViewId, null);
  assert.deepEqual(view.events[0], { seq: 1, type: "mediaFound", t: T0, pos: 0 });
  assert.deepEqual(view.events[1], { seq: 2, type: "play", t: T0 + 1000, pos: 0 });
});

test("seq is monotonic per View from 1, and each View counts independently", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  apply(s, { type: "OPEN", at: T0 + 7000, viewId: "view-2", view: { ...youtube, videoId: "other" } });
  apply(s, { type: "PLAY", at: T0 + 7500, pos: 0, viewId: "view-2" });

  assert.deepEqual(s.views["view-1"].events.map((e) => e.seq), [1, 2, 3]);
  assert.deepEqual(s.views["view-2"].events.map((e) => e.seq), [1, 2]);
});

test("a sample carries the two raw conditions and the sampled position", () => {
  const s = playing();
  apply(s, { type: "HIDE", at: T0 + 3000, pos: 2 });
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5.0004, playing: true, visible: false });

  assert.deepEqual(types(s, "view-1"), ["mediaFound", "play", "hidden", "sample"]);
  assert.deepEqual(s.views["view-1"].events.at(-1), {
    seq: 4,
    type: "sample",
    t: T0 + 6000,
    pos: 5,
    playing: true,
    visible: false,
  });
});

test("hidden-tab playback is reported raw — never labelled background", () => {
  const s = playing();
  apply(s, { type: "HIDE", at: T0 + 2000, pos: 1 });
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: false });
  const body = flush(s, T0 + 6000);

  const words = JSON.stringify(body);
  assert.ok(!words.includes("background"));
  assert.ok(!words.includes("watched"));
});

test("PiP and rate changes stay raw Events on the View", () => {
  const s = playing();
  apply(s, { type: "PIP_ENTER", at: T0 + 2000, pos: 1 });
  apply(s, { type: "RATE", at: T0 + 3000, pos: 2, rate: 2 });
  apply(s, { type: "RATE", at: T0 + 4000, pos: 4, rate: 2 }); // no change, no Event
  apply(s, { type: "PIP_LEAVE", at: T0 + 5000, pos: 6 });

  assert.deepEqual(types(s, "view-1"), ["mediaFound", "play", "pipEnter", "ratechange", "pipLeave"]);
  assert.equal(s.views["view-1"].events[3].rate, 2);
});

test("repeated play / pause / hide / show only emit on a real transition", () => {
  const s = playing();
  apply(s, { type: "PLAY", at: T0 + 2000, pos: 1 });
  apply(s, { type: "PAUSE", at: T0 + 3000, pos: 2 });
  apply(s, { type: "PAUSE", at: T0 + 3500, pos: 2 });
  apply(s, { type: "SHOW", at: T0 + 4000, pos: 2 });
  apply(s, { type: "HIDE", at: T0 + 5000, pos: 2 });

  assert.deepEqual(types(s, "view-1"), ["mediaFound", "play", "pause", "hidden"]);
});

test("visibility is a document fact — it reaches every open View in the frame", () => {
  const s = playing();
  apply(s, { type: "OPEN", at: T0 + 1000, viewId: "view-2", view: { ...youtube, videoId: "second" } });
  apply(s, { type: "HIDE", at: T0 + 2000 });

  assert.equal(types(s, "view-1").at(-1), "hidden");
  assert.equal(types(s, "view-2").at(-1), "hidden");
});

test("hiding with no View open is still remembered, so the next `visible` lands", () => {
  const s = initCapture(T0, { tabId: 41 });
  apply(s, { type: "HIDE", at: T0 + 1000 });
  assert.equal(s.tabVisible, false);

  apply(s, { type: "OPEN", at: T0 + 2000, viewId: "view-1", view: youtube });
  apply(s, { type: "PLAY", at: T0 + 3000, pos: 0 });
  apply(s, { type: "SHOW", at: T0 + 4000, pos: 1 });

  assert.deepEqual(types(s, "view-1"), ["mediaFound", "play", "visible"]);
});

test("a seek records where it came from and where it went", () => {
  const s = playing();
  apply(s, { type: "SEEKED", at: T0 + 13000, from: 10.6004, to: 45.2 });

  assert.deepEqual(s.views["view-1"].events.at(-1), {
    seq: 3,
    type: "seeked",
    t: T0 + 13000,
    pos: 45.2,
    from: 10.6,
    to: 45.2,
  });
});

test("resolved metadata updates the View header and records the moment", () => {
  const s = playing();
  apply(s, {
    type: "META",
    at: T0 + 500,
    changed: { title: "Never Gonna Give You Up", author: "Rick Astley" },
    metadataSource: "mediaSession",
  });

  const view = s.views["view-1"];
  assert.equal(view.title, "Never Gonna Give You Up");
  assert.equal(view.author, "Rick Astley");
  assert.equal(view.metadataSource, "mediaSession");
  assert.deepEqual(view.events.at(-1).changed, {
    title: "Never Gonna Give You Up",
    author: "Rick Astley",
  });
});

test("a new video id in the tab ends the View video-changed and links the next one", () => {
  const s = playing();
  apply(s, {
    type: "CHANGE_VIDEO",
    at: T0 + 18000,
    pos: 50.2,
    viewId: "view-2",
    view: { ...youtube, videoId: "kJQP7kiw5Fk", url: "https://www.youtube.com/watch?v=kJQP7kiw5Fk" },
  });

  const first = s.views["view-1"];
  assert.equal(first.open, false);
  assert.deepEqual(first.events.at(-1), {
    seq: 3,
    type: "viewEnded",
    t: T0 + 18000,
    pos: 50.2,
    reason: "video-changed",
  });

  const second = s.views["view-2"];
  assert.equal(second.previousViewId, "view-1");
  assert.equal(second.open, true);
  assert.equal(s.activeViewId, "view-2");
  assert.deepEqual(second.events[0], { seq: 1, type: "mediaFound", t: T0 + 18000, pos: 0 });
  // No `videoChange` on the wire — the pair of Events is the whole story.
  assert.ok(!JSON.stringify(flush(s)).includes("videoChange"));
});

test("a frame with two players says which View the new video replaced", () => {
  const s = playing();
  apply(s, { type: "OPEN", at: T0 + 500, viewId: "view-2", view: { ...youtube, videoId: "second" } });
  apply(s, {
    type: "CHANGE_VIDEO",
    at: T0 + 18000,
    pos: 50,
    fromViewId: "view-1",
    viewId: "view-3",
    view: youtube,
  });

  assert.equal(s.views["view-1"].open, false);
  assert.equal(s.views["view-2"].open, true);
  assert.equal(s.views["view-3"].previousViewId, "view-1");
});

test("natural media end is an `ended` Event, not the end of the View", () => {
  const s = playing();
  apply(s, { type: "MEDIA_ENDED", at: T0 + 213000, pos: 213 });

  assert.equal(s.views["view-1"].open, true);
  assert.equal(types(s, "view-1").at(-1), "ended");

  apply(s, { type: "PLAY", at: T0 + 214000, pos: 0 });
  assert.equal(types(s, "view-1").at(-1), "play");
});

test("navigating away ends the View and leaves nothing active", () => {
  const s = playing();
  apply(s, { type: "VIEW_ENDED", at: T0 + 9000, pos: 8, reason: "nav" });

  assert.equal(s.views["view-1"].open, false);
  assert.equal(s.activeViewId, null);
  assert.equal(s.views["view-1"].events.at(-1).reason, "nav");
});

test("an ended View ignores later Events", () => {
  const s = playing();
  apply(s, { type: "VIEW_ENDED", at: T0 + 9000, pos: 8, reason: "tab-closed" });
  apply(s, { type: "PLAY", at: T0 + 10000, pos: 8, viewId: "view-1" });

  assert.equal(types(s, "view-1").at(-1), "viewEnded");
});

test("END_OPEN_VIEWS closes an open View as crash-recovered, stamped at the last sample", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  apply(s, { type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: true });
  // The browser dies here: nothing observes it, so no Event marks it.
  apply(s, { type: "END_OPEN_VIEWS", reason: "crash-recovered", at: T0 + 900000 });

  const view = s.views["view-1"];
  assert.equal(view.open, false);
  assert.deepEqual(view.events.at(-1), {
    seq: 5,
    type: "viewEnded",
    t: T0 + 11000,
    pos: 10,
    reason: "crash-recovered",
  });
});

test("END_OPEN_VIEWS with no sample yet falls back to the View's own start", () => {
  const s = playing();
  apply(s, { type: "END_OPEN_VIEWS", reason: "crash-recovered", at: T0 + 900000 });

  assert.deepEqual(s.views["view-1"].events.at(-1), {
    seq: 3,
    type: "viewEnded",
    t: T0,
    pos: 0,
    reason: "crash-recovered",
  });
});

test("buildFlush produces a schema-v1 envelope carrying the View header", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  const body = flush(s, T0 + 6000);

  assert.equal(body.schemaVersion, SCHEMA_VERSION);
  assert.equal(body.flushId, "flush-1");
  assert.equal(body.sentAt, T0 + 6000);
  assert.deepEqual(body.agent, agent);
  assert.equal(body.views.length, 1);
  assert.deepEqual(Object.keys(body.views[0]).sort(), [
    "adapterId", "artworkUrl", "author", "contentFormat", "durationSec", "embedded",
    "events", "metadataSource", "open", "previousViewId", "service", "startedAt",
    "tabId", "title", "url", "videoId", "viewId",
  ]);
  assert.equal(body.views[0].open, true);
});

test("an embedded player rides the wire with embedded = true", () => {
  const s = initCapture(T0, { tabId: 7 });
  apply(s, {
    type: "OPEN",
    at: T0,
    viewId: "view-e",
    view: { ...youtube, embedded: true, url: "https://someblog.example/post/hi" },
  });

  assert.equal(flush(s).views[0].embedded, true);
});

test("a heartbeat Flush with nothing buffered has empty views", () => {
  assert.deepEqual(flush(initCapture(T0)).views, []);
});

test("an Ack prunes every Event with seq <= ackSeq for that View", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  const first = flush(s, T0 + 6000);
  assert.deepEqual(first.views[0].events.map((e) => e.seq), [1, 2, 3]);

  s.lastFlushAckSeq["view-1"] = 3;
  // Nothing new to say about an open View: it drops out of the next Flush.
  assert.deepEqual(flush(s, T0 + 7000).views, []);

  apply(s, { type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: true });
  const second = flush(s, T0 + 11000);
  assert.deepEqual(second.views[0].events.map((e) => e.seq), [4]);
});

test("an unacknowledged batch is re-sent whole on the next Flush", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  flush(s, T0 + 6000); // the Ack never arrives
  apply(s, { type: "SAMPLE", at: T0 + 11000, pos: 10, playing: true, visible: true });

  assert.deepEqual(flush(s, T0 + 11000).views[0].events.map((e) => e.seq), [1, 2, 3, 4]);
});

test("a closed View rides one Flush, then stops once it is fully Ack'd", () => {
  const s = playing();
  apply(s, { type: "VIEW_ENDED", at: T0 + 9000, pos: 8, reason: "nav" });

  const body = flush(s, T0 + 9000);
  assert.equal(body.views[0].open, false);
  assert.deepEqual(body.views[0].events.map((e) => e.seq), [1, 2, 3]);

  s.lastFlushAckSeq["view-1"] = 3;
  s.flushedClosed["view-1"] = true;
  assert.deepEqual(flush(s, T0 + 10000).views, []);
});

test("a closed View whose Ack was lost is re-sent, still marked closed", () => {
  const s = playing();
  apply(s, { type: "VIEW_ENDED", at: T0 + 9000, pos: 8, reason: "nav" });
  flush(s, T0 + 9000); // lost Ack

  const retry = flush(s, T0 + 14000);
  assert.equal(retry.views.length, 1);
  assert.equal(retry.views[0].open, false);
  assert.deepEqual(retry.views[0].events.map((e) => e.seq), [1, 2, 3]);
});

test("Views ride the wire in the order they started", () => {
  const s = playing();
  apply(s, { type: "CHANGE_VIDEO", at: T0 + 18000, pos: 50, viewId: "view-2", view: youtube });
  apply(s, { type: "PLAY", at: T0 + 19000, pos: 0 });

  assert.deepEqual(flush(s, T0 + 19000).views.map((v) => v.viewId), ["view-1", "view-2"]);
});

test("one Flush is capped, so a long offline stretch still fits in a body", () => {
  const s = playing();
  for (let beat = 1; beat <= 20; beat += 1) {
    apply(s, { type: "SAMPLE", at: T0 + beat * 5000, pos: beat * 5, playing: true, visible: true });
  }

  const first = buildFlush(s, { flushId: "f-1", sentAt: T0, agent, maxEvents: 8 });
  assert.deepEqual(first.views[0].events.map((e) => e.seq), [1, 2, 3, 4, 5, 6, 7, 8]);

  s.lastFlushAckSeq["view-1"] = 8;
  const second = buildFlush(s, { flushId: "f-2", sentAt: T0, agent, maxEvents: 8 });
  assert.deepEqual(second.views[0].events.map((e) => e.seq), [9, 10, 11, 12, 13, 14, 15, 16]);
});

test("the cap is spent across Views, oldest first", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  apply(s, { type: "OPEN", at: T0 + 7000, viewId: "view-2", view: youtube });
  apply(s, { type: "PLAY", at: T0 + 8000, pos: 0 });

  const body = buildFlush(s, { flushId: "f-1", sentAt: T0, agent, maxEvents: 4 });
  assert.deepEqual(body.views.map((v) => v.viewId), ["view-1", "view-2"]);
  assert.deepEqual(body.views[1].events.map((e) => e.seq), [1]);
});

test("a truncated batch reports the View as open — it isn't carrying the viewEnded", () => {
  const s = playing();
  apply(s, { type: "VIEW_ENDED", at: T0 + 9000, pos: 8, reason: "nav" });
  assert.equal(s.views["view-1"].open, false);

  const truncated = buildFlush(s, { flushId: "f-1", sentAt: T0, agent, maxEvents: 2 });
  assert.equal(truncated.views[0].open, true);
  assert.deepEqual(truncated.views[0].events.map((e) => e.seq), [1, 2]);

  s.lastFlushAckSeq["view-1"] = 2;
  const rest = buildFlush(s, { flushId: "f-2", sentAt: T0, agent, maxEvents: 2 });
  assert.equal(rest.views[0].open, false);
});

test("closing an unobserved View takes the reason it deserves", () => {
  const s = playing();
  apply(s, { type: "SAMPLE", at: T0 + 6000, pos: 5, playing: true, visible: true });
  apply(s, { type: "END_OPEN_VIEWS", reason: "tab-closed", at: T0 + 900000 });

  assert.deepEqual(s.views["view-1"].events.at(-1), {
    seq: 4,
    type: "viewEnded",
    t: T0 + 6000,
    pos: 5,
    reason: "tab-closed",
  });
});

test("the module never reaches for a DOM or an extension API", async () => {
  const source = await (await import("node:fs/promises")).readFile(
    new URL("../src/capture.js", import.meta.url),
    "utf8",
  );
  for (const forbidden of ["document", "window", "navigator", "chrome.", "browser."]) {
    assert.ok(!source.includes(forbidden), `capture.js must not mention ${forbidden}`);
  }
});
