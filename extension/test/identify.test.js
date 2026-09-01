// Generic, best-effort identification: who is the Service, which video is this,
// is the player embedded, and what does `mediaSession` know. Per-Service
// Adapters are a later slice — until then everything here is derived from the
// page URL, the media element, and `mediaSession`.

import test from "node:test";
import assert from "node:assert/strict";
import {
  contentFormatFor,
  durationOf,
  fromMediaSession,
  identify,
  isEmbedded,
  metadataDiff,
  normalizeUrl,
  serviceFor,
} from "../src/identify.js";

test("the Service of a site with no Adapter is its bare hostname", () => {
  assert.equal(serviceFor("https://www.youtube.com/watch?v=abc"), "youtube.com");
  assert.equal(serviceFor("https://cdn.example.co.uk/v/clip.mp4"), "cdn.example.co.uk");
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

test("the wire url keeps the host as it is; only the id ignores a `www.`", () => {
  const bare = identify({ frameUrl: "https://youtube.com/watch?v=abc" });
  const dubdub = identify({ frameUrl: "https://www.youtube.com/watch?v=abc" });
  assert.equal(dubdub.url, "https://www.youtube.com/watch?v=abc");
  assert.equal(bare.videoIdSource, dubdub.videoIdSource);
});

test("the id source is order-insensitive about query params", () => {
  assert.equal(
    normalizeUrl("https://v.example/play?b=2&a=1"),
    normalizeUrl("https://v.example/play?a=1&b=2"),
  );
});

test("a page URL is not a resolvable id on its own when the media has its own source", () => {
  const first = identify({ frameUrl: "https://blog.example/post", mediaSrc: "https://cdn.example/a.mp4" });
  const second = identify({ frameUrl: "https://blog.example/post", mediaSrc: "https://cdn.example/b.mp4" });
  assert.notEqual(first.videoIdSource, second.videoIdSource);
});

test("a blob or data source is not identifying, so the page URL carries the id", () => {
  const withBlob = identify({ frameUrl: "https://v.example/watch?id=7", mediaSrc: "blob:https://v.example/9f2a" });
  const without = identify({ frameUrl: "https://v.example/watch?id=7", mediaSrc: "" });
  assert.equal(withBlob.videoIdSource, without.videoIdSource);
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

test("identify assembles the View header a page helper can open on", () => {
  const view = identify({
    frameUrl: "https://www.youtube.com/embed/aQ8xEjc0M2k?autoplay=1",
    topUrl: "https://someblog.example/post/hi",
    isTopFrame: false,
    mediaSrc: "blob:https://www.youtube.com/9f2a",
    duration: 640,
  });

  assert.equal(view.service, "youtube.com");
  assert.equal(view.embedded, true);
  assert.equal(view.contentFormat, "standard");
  assert.equal(view.durationSec, 640);
  assert.equal(view.url, "https://www.youtube.com/embed/aQ8xEjc0M2k");
  assert.equal(view.metadataSource, "generic");
  assert.equal(view.adapterId, null);
});

test("mediaSession metadata becomes the View's title, author and artwork", () => {
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
    artworkUrl: "https://i.ytimg.com/vi/x/large.jpg",
  });
});

test("no mediaSession metadata is no metadata, not empty strings", () => {
  assert.deepEqual(fromMediaSession(null), {});
  assert.deepEqual(fromMediaSession({ title: "", artist: "", artwork: [] }), {});
});

test("a metadata diff reports only what actually changed", () => {
  const view = { title: "Loading…", author: null, artworkUrl: null, durationSec: null };
  assert.deepEqual(
    metadataDiff(view, { title: "Real Title", author: null, durationSec: 213 }),
    { title: "Real Title", durationSec: 213 },
  );
  assert.equal(metadataDiff(view, { title: "Loading…" }), null);
  assert.equal(metadataDiff(view, {}), null);
});
