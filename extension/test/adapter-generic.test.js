// The fallback: what can be known about a video on a site nobody wrote a
// reader for. Every field here is the last rung of some ranking in
// `metadata.js`.

import test from "node:test";
import assert from "node:assert/strict";
import { readGeneric } from "../src/adapters/generic.js";
import { fakeDocument } from "./helpers/fake-document.js";

function read(href, { elements = {}, title = "", ...rest } = {}) {
  return readGeneric({
    location: new URL(href),
    document: fakeDocument(elements, { title }),
    ...rest,
  });
}

test("the id is the address with the query and the fragment taken off", () => {
  const page = "https://www.bbc.co.uk/iplayer/episode/m001";
  assert.equal(read(page).videoIdSource, "https://bbc.co.uk/iplayer/episode/m001");
  assert.equal(read(`${page}?autoplay=1#top`).videoIdSource, read(page).videoIdSource);
  // `www.` is noise: it must not split one site into two.
  assert.equal(read("https://bbc.co.uk/iplayer/episode/m001").videoIdSource, read(page).videoIdSource);
});

// The accepted cost of dropping the query. A site that keeps its id in `?v=`
// collapses all its videos into one — and those are exactly the sites that
// then surface in the app's "needs an Adapter" flag, which is how you find
// them.
test("a site hiding its id in the query collapses to one id", () => {
  assert.equal(
    read("https://videos.example.com/player?v=first").videoIdSource,
    read("https://videos.example.com/player?v=second").videoIdSource,
  );
});

test("two players in one frame are told apart by their own sources, on request", () => {
  const page = "https://example.com/gallery";
  const one = read(page, { mediaSrc: "https://example.com/a.mp4", disambiguate: true });
  const two = read(page, { mediaSrc: "https://example.com/b.mp4", disambiguate: true });
  assert.notEqual(one.videoIdSource, two.videoIdSource);
  // The first player in a frame is not disambiguated, so the lone-player case
  // keeps the clean page-address id.
  assert.equal(read(page, { mediaSrc: "https://example.com/a.mp4" }).videoIdSource, "https://example.com/gallery");
});

test("a blob or data source cannot tell anything apart", () => {
  const page = "https://example.com/gallery";
  assert.equal(read(page, { mediaSrc: "blob:https://example.com/x", disambiguate: true }).videoIdSource, page);
});

test("the Service is the site's own domain", () => {
  assert.equal(read("https://iplayer.bbc.co.uk/x").service, "bbc.co.uk");
  assert.equal(read("https://music.youtube.com/watch?v=abc").service, "youtube.com");
});

test("the title is og:title, then the browser tab, and they are told apart", () => {
  const withOg = read("https://example.com/v", {
    elements: { "meta[property='og:title']": { content: "The Real Title" } },
    title: "The Real Title | Example",
  });
  assert.equal(withOg.title, "The Real Title");
  assert.equal(withOg.documentTitle, "The Real Title | Example");

  const withoutOg = read("https://example.com/v", { title: "The Real Title | Example" });
  assert.equal(withoutOg.title, undefined);
  assert.equal(withoutOg.documentTitle, "The Real Title | Example");
});

test("a media element with no finite length is a livestream", () => {
  assert.equal(read("https://example.com/v", { duration: Infinity }).contentFormat, "live");
  assert.equal(read("https://example.com/v", { duration: 213 }).contentFormat, "standard");
  assert.equal(read("https://example.com/v", { duration: NaN }).contentFormat, "standard");
});

test("the length is reported only when the player really knows it", () => {
  assert.equal(read("https://example.com/v", { duration: 213.04 }).durationSec, 213.04);
  assert.equal(read("https://example.com/v", { duration: Infinity }).durationSec, null);
  assert.equal(read("https://example.com/v", { duration: NaN }).durationSec, null);
});

test("the fallback never claims to be sure", () => {
  assert.equal(read("https://example.com/v").confidence, "fallback");
});
