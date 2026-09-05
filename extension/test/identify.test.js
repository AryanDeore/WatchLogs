// The pure helpers behind the generic fallback: who is the Service, is the
// player embedded, and what does `mediaSession` know. Assembling them into a
// View header is `adapters/generic.js`, and is tested there.

import test from "node:test";
import assert from "node:assert/strict";
import {
  contentFormatFor,
  durationOf,
  fromMediaSession,
  isEmbedded,
  isMediaSwap,
  metadataDiff,
  normalizeUrl,
  serviceFor,
} from "../src/identify.js";

test("a URL that does not parse still reports a Service", () => {
  assert.equal(serviceFor("not a url"), "unknown");
});

// A View's `service` rides the wire as a required, non-empty field
// (SCHEMA.md); the App's decoder 400s the whole Flush otherwise. A URL that
// parses but has no host — `about:blank` (every `match_about_blank` iframe),
// `about:srcdoc`, `file:` — must not slip an empty string past `serviceFor`.
test("a URL that parses but has no host still reports a Service", () => {
  assert.equal(serviceFor("about:blank"), "unknown");
  assert.equal(serviceFor("about:srcdoc"), "unknown");
  assert.equal(serviceFor("file:///Users/me/clip.html"), "unknown");
});

test("the id source keeps the params that pick the video and drops the noise", () => {
  const canonical = normalizeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
  for (const noisy of [
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=4",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=newsletter&si=xyz",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ#comments",
  ]) {
    assert.equal(normalizeUrl(noisy), canonical, noisy);
  }
});

test("the id source separates two different videos on one site", () => {
  assert.notEqual(
    normalizeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
    normalizeUrl("https://www.youtube.com/watch?v=kJQP7kiw5Fk"),
  );
  assert.notEqual(
    normalizeUrl("https://www.netflix.com/watch/81234567"),
    normalizeUrl("https://www.netflix.com/watch/81234568"),
  );
});

test("the id source is order-insensitive about query params", () => {
  assert.equal(
    normalizeUrl("https://v.example/play?b=2&a=1"),
    normalizeUrl("https://v.example/play?a=1&b=2"),
  );
});

test("a player on the Service's own site is not embedded", () => {
  assert.equal(isEmbedded({ isTopFrame: true, frameUrl: "https://www.youtube.com/watch?v=a" }), false);
  assert.equal(
    isEmbedded({
      isTopFrame: false,
      frameUrl: "https://player.vimeo.com/video/9",
      topUrl: "https://vimeo.com/9",
    }),
    false,
  );
});

test("a player inside a third-party page is embedded", () => {
  assert.equal(
    isEmbedded({
      isTopFrame: false,
      frameUrl: "https://www.youtube.com/embed/aQ8xEjc0M2k",
      topUrl: "https://someblog.example/post/hi",
    }),
    true,
  );
});

test("a cross-origin frame whose ancestor is unreadable is treated as embedded", () => {
  assert.equal(isEmbedded({ isTopFrame: false, frameUrl: "https://www.youtube.com/embed/x" }), true);
});

test("contentFormat is a best guess: live when the media has no finite duration", () => {
  assert.equal(contentFormatFor(213), "standard");
  assert.equal(contentFormatFor(Infinity), "live");
  assert.equal(contentFormatFor(NaN), "standard");
  assert.equal(contentFormatFor(null), "standard");
});

test("durationSec is null unless the player really knows it", () => {
  assert.equal(durationOf(213.4), 213.4);
  assert.equal(durationOf(Infinity), null);
  assert.equal(durationOf(NaN), null);
  assert.equal(durationOf(0), null);
});

// Artwork is present on the metadata and dropped on the floor: #4 took the
// thumbnail out of the schema entirely, so nothing downstream can store one.
test("mediaSession metadata becomes the View's title and author, and no artwork", () => {
  const metadata = fromMediaSession({
    title: "Never Gonna Give You Up",
    artist: "Rick Astley",
    artwork: [
      { src: "https://i.ytimg.com/vi/x/small.jpg", sizes: "96x96" },
      { src: "https://i.ytimg.com/vi/x/large.jpg", sizes: "512x512" },
    ],
  });

  assert.deepEqual(metadata, {
    title: "Never Gonna Give You Up",
    author: "Rick Astley",
  });
});

test("no mediaSession metadata is no metadata, not empty strings", () => {
  assert.deepEqual(fromMediaSession(null), {});
  assert.deepEqual(fromMediaSession({ title: "", artist: "", artwork: [] }), {});
});

test("a metadata diff reports only what actually changed", () => {
  const view = { title: "Loading…", author: null, durationSec: null };
  assert.deepEqual(
    metadataDiff(view, { title: "Real Title", author: null, durationSec: 213 }),
    { title: "Real Title", durationSec: 213 },
  );
  assert.equal(metadataDiff(view, { title: "Loading…" }), null);
  assert.equal(metadataDiff(view, {}), null);
});

test("one player handed a second video is a swap, whatever the address bar still says", () => {
  // The Shorts feed, mid-scroll: the element already holds the next Short's
  // media while the URL — and so the View's id — is still the last one's.
  assert.equal(
    isMediaSwap({ openedWith: "blob:https://www.youtube.com/aaaa", current: "blob:https://www.youtube.com/bbbb" }),
    true,
  );
  // The same video playing on: nothing to refuse.
  assert.equal(
    isMediaSwap({ openedWith: "blob:https://www.youtube.com/aaaa", current: "blob:https://www.youtube.com/aaaa" }),
    false,
  );
});

test("a player with nothing to compare against is not a swap", () => {
  // A player built before its media is attached, and one that has just been
  // emptied: neither says the View has moved to another video.
  assert.equal(isMediaSwap({ openedWith: "", current: "https://example.com/a.webm" }), false);
  assert.equal(isMediaSwap({ openedWith: "https://example.com/a.webm", current: "" }), false);
  assert.equal(isMediaSwap({}), false);
});
