// The YouTube Adapter's URL reading and its ranking of what it finds on the
// page. The selectors themselves are pinned against real saved pages in
// `test-e2e/adapters.spec.js` — a fake document proves the logic, not that
// `#above-the-fold h1` is still where YouTube keeps the title.

import test from "node:test";
import assert from "node:assert/strict";
import { YouTubeAdapter } from "../src/adapters/youtube.js";
import { fakeDocument } from "./helpers/fake-document.js";

function read(href, elements = {}) {
  return YouTubeAdapter.create({
    location: new URL(href),
    document: fakeDocument(elements),
  }).read();
}

const WATCH_PAGE = {
  "#above-the-fold h1": "Rick Astley - Never Gonna Give You Up (Official Video)",
  "yt-formatted-string#text.ytd-channel-name": "Rick Astley",
};

test("a watch URL takes its id from `v` and reads as standard", () => {
  const snapshot = read("https://www.youtube.com/watch?v=dQw4w9WgXcQ", WATCH_PAGE);
  assert.equal(snapshot.videoId, "dQw4w9WgXcQ");
  assert.equal(snapshot.contentFormat, "standard");
  assert.equal(snapshot.title, "Rick Astley - Never Gonna Give You Up (Official Video)");
  assert.equal(snapshot.author, "Rick Astley");
  assert.equal(snapshot.confidence, "high");
});

test("a video opened from a playlist is still that video, not the playlist", () => {
  assert.equal(read("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=4").videoId, "dQw4w9WgXcQ");
});

test("shorts and /live paths take their id from the path", () => {
  assert.deepEqual(
    (({ videoId, contentFormat }) => ({ videoId, contentFormat }))(read("https://www.youtube.com/shorts/x8kL9mQ2vNc")),
    { videoId: "x8kL9mQ2vNc", contentFormat: "short" },
  );
  assert.deepEqual(
    (({ videoId, contentFormat }) => ({ videoId, contentFormat }))(read("https://www.youtube.com/live/jfKfPfyJRdk")),
    { videoId: "jfKfPfyJRdk", contentFormat: "standard" },
  );
});

test("an embed knows it is in someone else's page, on either host", () => {
  for (const host of ["www.youtube.com", "www.youtube-nocookie.com"]) {
    const snapshot = read(`https://${host}/embed/dQw4w9WgXcQ`);
    assert.equal(snapshot.videoId, "dQw4w9WgXcQ", host);
    assert.equal(snapshot.contentFormat, "standard", host);
    assert.equal(snapshot.embedded, true, host);
  }
});

// The `<video>` element's `.duration` never resolves for a player YouTube built
// in a background tab (#41), so the Adapter reads the length off the page's own
// SEO markup instead.
test("a watch page's duration markup becomes the View's length", () => {
  const snapshot = read("https://www.youtube.com/watch?v=dQw4w9WgXcQ", {
    ...WATCH_PAGE,
    'meta[itemprop="duration"]': { content: "PT3M34S" },
  });
  assert.equal(snapshot.durationSec, 214);
});

test("a very large duration placeholder is never reported as a fixed length", () => {
  const snapshot = read("https://www.youtube.com/watch?v=jfKfPfyJRdk", {
    ...WATCH_PAGE,
    'meta[itemprop="duration"]': { content: "PT2026691M52S" },
  });
  assert.equal(snapshot.contentFormat, "standard");
  assert.equal("durationSec" in snapshot, false);
});

test("a page with no duration markup reports no length, not zero", () => {
  const snapshot = read("https://www.youtube.com/shorts/x8kL9mQ2vNc");
  assert.equal("durationSec" in snapshot, false);
});

test("an Adapter that found an id but no title is not confident", () => {
  const snapshot = read("https://www.youtube.com/shorts/x8kL9mQ2vNc");
  assert.equal(snapshot.videoId, "x8kL9mQ2vNc");
  assert.equal(snapshot.confidence, "low");
  assert.equal(snapshot.title, undefined);
});

test("the Adapter steps aside from a page with no video of its own", () => {
  for (const url of [
    "https://www.youtube.com/",
    "https://www.youtube.com/@RickAstleyYT",
    "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
    "https://www.youtube.com/playlist?list=PL123",
    "https://www.youtube.com/feed/subscriptions",
    "https://www.youtube.com/watch?list=PL123",
    "https://www.youtube.com/shorts/",
  ]) {
    assert.equal(YouTubeAdapter.matches(new URL(url)), false, url);
  }
});

test("YouTube Music is not handled here", () => {
  assert.equal(YouTubeAdapter.matches(new URL("https://music.youtube.com/watch?v=dQw4w9WgXcQ")), false);
  assert.equal(YouTubeAdapter.matches(new URL("https://www.youtube.com/watch?v=dQw4w9WgXcQ")), true);
});

test("the Adapter never names the Service — the router does", () => {
  assert.equal("service" in read("https://www.youtube.com/watch?v=dQw4w9WgXcQ", WATCH_PAGE), false);
});
