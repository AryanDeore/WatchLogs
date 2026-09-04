// The ranking, one field at a time. Every case here is four bags of plain
// values in and one header out — no page, no player, no browser.

import test from "node:test";
import assert from "node:assert/strict";
import { merge } from "../src/metadata.js";

/** youtube.com/watch?v=dQw4w9WgXcQ, everything readable, nothing broken. */
function watchPage(overrides = {}) {
  return {
    router: { service: "youtube", embedded: false, adapterId: "youtube" },
    adapter: {
      videoId: "dQw4w9WgXcQ",
      contentFormat: "standard",
      title: "Rick Astley - Never Gonna Give You Up (Official Video)",
      author: "Rick Astley",
      durationSec: 213,
      confidence: "high",
    },
    session: { title: "Never Gonna Give You Up", author: "Rick Astley" },
    element: { durationSec: 213.04 },
    generic: {
      service: "youtube.com",
      videoId: "sha1:4f2a9c",
      url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      contentFormat: "standard",
      documentTitle: "Rick Astley - Never Gonna Give You Up (Official Video) - YouTube",
    },
    ...overrides,
  };
}

test("a page every source can read: the Adapter takes the id, mediaSession takes the title", () => {
  const header = merge(watchPage());
  assert.equal(header.videoId, "dQw4w9WgXcQ");
  assert.equal(header.service, "youtube");
  assert.equal(header.contentFormat, "standard");
  // The lock-screen string, not the Adapter's "<channel> - <title>" and not the
  // tab title's "- YouTube" suffix.
  assert.equal(header.title, "Never Gonna Give You Up");
  assert.equal(header.author, "Rick Astley");
  assert.equal(header.durationSec, 213);
  assert.equal(header.metadataSource, "mediaSession");
  assert.equal(header.adapterId, "youtube");
});

test("the Service is the router's; the Adapter never sets it", () => {
  const header = merge(watchPage());
  // The generic reading said "youtube.com"; the router's "youtube" outranks it.
  assert.equal(header.service, "youtube");
  assert.equal(merge({ generic: { service: "bbc.co.uk" } }).service, "bbc.co.uk");
  assert.equal(merge({}).service, "unknown");
});

test("mediaSession never supplies the id or the format, however loudly it talks", () => {
  const header = merge({
    session: { title: "Never Gonna Give You Up", videoId: "nonsense", contentFormat: "live" },
    generic: { videoId: "sha1:4f2a9c", contentFormat: "standard" },
  });
  assert.equal(header.videoId, "sha1:4f2a9c");
  assert.equal(header.contentFormat, "standard");
});

// 9:52pm, swiping Shorts. YouTube moved the element the Adapter reads the title
// from, so the title lookup comes back empty and the Adapter reports `low`. The
// id still came off the address bar, and that is what has to survive.
test("a shaky Adapter keeps the id and the format but loses the prose", () => {
  const header = merge({
    router: { service: "youtube", embedded: false, adapterId: "youtube" },
    adapter: {
      videoId: "x8kL9mQ2vNc",
      contentFormat: "short",
      author: "Cat Channel",
      confidence: "low",
    },
    session: { title: "Cat does backflip", author: "cats_of_instagram" },
    generic: { videoId: "sha1:beef", contentFormat: "standard", documentTitle: "Shorts - YouTube" },
  });
  assert.equal(header.videoId, "x8kL9mQ2vNc");
  assert.equal(header.contentFormat, "short");
  assert.equal(header.title, "Cat does backflip");
  // The tie-break's one real effect: `author` flips to mediaSession.
  assert.equal(header.author, "cats_of_instagram");
});

test("a confident Adapter takes the author back off mediaSession", () => {
  const header = merge({
    adapter: { videoId: "x8kL9mQ2vNc", author: "Cat Channel", title: "Backflip", confidence: "high" },
    session: { title: "Cat does backflip", author: "cats_of_instagram" },
  });
  assert.equal(header.author, "Cat Channel");
  // ...but not the title. mediaSession outranks a confident Adapter there too.
  assert.equal(header.title, "Cat does backflip");
  assert.equal(header.metadataSource, "mediaSession");
});

test("the title walks all four rungs and reports which one it stopped on", () => {
  const rungs = [
    [{ session: { title: "lock screen" } }, "lock screen", "mediaSession"],
    [{ adapter: { title: "off the page", confidence: "high" } }, "off the page", "adapter"],
    [{ generic: { title: "og:title" } }, "og:title", "generic"],
    [{ generic: { documentTitle: "tab title" } }, "tab title", "documentTitle"],
    [{}, null, null],
  ];
  for (const [sources, title, source] of rungs) {
    const header = merge(sources);
    assert.equal(header.title, title);
    assert.equal(header.metadataSource, source, JSON.stringify(sources));
  }
});

test("a source with nothing to say is stepped over, not taken as an answer", () => {
  const header = merge({
    session: { title: null, author: undefined },
    adapter: { title: undefined, author: "Rick Astley", confidence: "high" },
    generic: { title: "", documentTitle: "tab title" },
  });
  assert.equal(header.title, "tab title");
  assert.equal(header.metadataSource, "documentTitle");
  assert.equal(header.author, "Rick Astley");
});

// 9:19pm, Glass Onion. A film genuinely has no show name, and the Netflix
// Adapter says so. If that empty string meant "keep looking", `author` would
// fall through to mediaSession and a creator named "Netflix" would start
// accruing hours.
test("an Adapter's empty string is an answer; anyone else's is a gap", () => {
  const film = merge({
    router: { service: "netflix", adapterId: "netflix" },
    adapter: { videoId: "81444554", title: "Glass Onion", author: "", confidence: "high" },
    session: { author: "Netflix" },
  });
  assert.equal(film.author, "");

  const gap = merge({ generic: { author: "" }, session: { author: "Netflix" } });
  assert.equal(gap.author, "Netflix");
});

test("the router proposes `embedded` and only the Adapter may correct it", () => {
  const proposed = { router: { embedded: true } };
  assert.equal(merge(proposed).embedded, true);
  assert.equal(merge({ ...proposed, session: { embedded: false } }).embedded, true);
  assert.equal(
    merge({ ...proposed, adapter: { embedded: false, confidence: "high" } }).embedded,
    false,
  );
  // Silence is not a correction.
  assert.equal(merge({ ...proposed, adapter: { confidence: "high" } }).embedded, true);
});

test("the length falls from the Adapter to the player to mediaSession", () => {
  const adapter = { confidence: "high" };
  assert.equal(merge({ adapter: { ...adapter, durationSec: 213 }, element: { durationSec: 213.04 } }).durationSec, 213);
  assert.equal(merge({ adapter, element: { durationSec: 213.04 }, session: { durationSec: 999 } }).durationSec, 213.04);
  assert.equal(merge({ adapter, session: { durationSec: 999 } }).durationSec, 999);
  // A live stream: the player reads `Infinity`, the caller filters it to null,
  // and nothing below it knows either.
  assert.equal(merge({ adapter, element: { durationSec: null } }).durationSec, null);
});

test("the format falls back to `standard` when nobody says otherwise", () => {
  assert.equal(merge({}).contentFormat, "standard");
  assert.equal(merge({ generic: { contentFormat: "live" } }).contentFormat, "live");
  assert.equal(
    merge({ adapter: { contentFormat: "short", confidence: "high" }, generic: { contentFormat: "live" } }).contentFormat,
    "short",
  );
});

test("no path through the merge produces an artworkUrl", () => {
  const header = merge({
    ...watchPage(),
    session: { title: "t", author: "a", artworkUrl: "https://i.ytimg.com/vi/x/hq.jpg" },
    adapter: { videoId: "x", confidence: "high", artworkUrl: "https://i.ytimg.com/vi/x/hq.jpg" },
  });
  assert.ok(!("artworkUrl" in header));
});
