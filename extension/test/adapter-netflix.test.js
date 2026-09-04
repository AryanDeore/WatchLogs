// The Netflix Adapter. Flat metadata by design: no season or episode-number
// fields on the wire, so an episode's identity has to survive inside `title`.

import test from "node:test";
import assert from "node:assert/strict";
import { NetflixAdapter } from "../src/adapters/netflix.js";
import { fakeDocument } from "./helpers/fake-document.js";

function read(href, elements = {}) {
  return NetflixAdapter.create({
    location: new URL(href),
    document: fakeDocument(elements),
  }).read();
}

test("an episode is the show as author and `show - episode` as title", () => {
  const snapshot = read("https://www.netflix.com/watch/81234567", {
    "[data-uia=video-title] h4": "Stranger Things",
    "[data-uia=video-title] span:last-of-type": "Chapter Four: The Sauna Test",
  });
  assert.equal(snapshot.videoId, "81234567");
  assert.equal(snapshot.contentFormat, "standard");
  assert.equal(snapshot.author, "Stranger Things");
  assert.equal(snapshot.title, "Stranger Things - Chapter Four: The Sauna Test");
  assert.equal(snapshot.confidence, "high");
});

// A film has no show name, and saying so is different from failing to find
// one: an empty author stops the ranking, so mediaSession cannot fill it with
// "Netflix" and grow a fake creator in the By Service pane.
test("a film is its own title and an author of nothing at all", () => {
  const snapshot = read("https://www.netflix.com/watch/81444554", {
    "[data-uia=video-title] h4": "Glass Onion: A Knives Out Mystery",
  });
  assert.equal(snapshot.title, "Glass Onion: A Knives Out Mystery");
  assert.equal(snapshot.author, "");
});

test("the older class-based markup reads the same as the current one", () => {
  const snapshot = read("https://www.netflix.com/watch/81234567", {
    ".video-title h4": "Stranger Things",
    ".video-title span:last-of-type": "Chapter Four: The Sauna Test",
  });
  assert.equal(snapshot.title, "Stranger Things - Chapter Four: The Sauna Test");
});

test("the id is the number in the path, whatever trails it", () => {
  assert.equal(read("https://www.netflix.com/watch/81234567?trackId=1234").videoId, "81234567");
  assert.equal(read("https://www.netflix.com/gb/watch/81234567").videoId, "81234567");
});

test("a title the player has not drawn yet is no title, and no confidence", () => {
  const snapshot = read("https://www.netflix.com/watch/81234567");
  assert.equal(snapshot.videoId, "81234567");
  assert.equal(snapshot.title, undefined);
  assert.equal(snapshot.author, undefined);
  assert.equal(snapshot.confidence, "low");
});

test("the Adapter steps aside from browsing, and takes the watch page", () => {
  assert.equal(NetflixAdapter.matches(new URL("https://www.netflix.com/browse")), false);
  assert.equal(NetflixAdapter.matches(new URL("https://www.netflix.com/title/81234567")), false);
  assert.equal(NetflixAdapter.matches(new URL("https://www.netflix.com/")), false);
  assert.equal(NetflixAdapter.matches(new URL("https://www.netflix.com/watch/81234567")), true);
});

test("Netflix has no Shorts and no live, so the format never moves", () => {
  assert.equal(read("https://www.netflix.com/watch/81234567").contentFormat, "standard");
});
