import test from "node:test";
import assert from "node:assert/strict";
import { registrableDomain, serviceFor } from "../src/identify.js";

test("the registrable domain is the last two labels", () => {
  assert.equal(registrableDomain("www.youtube.com"), "youtube.com");
  assert.equal(registrableDomain("music.youtube.com"), "youtube.com");
  assert.equal(registrableDomain("youtube.com"), "youtube.com");
  assert.equal(registrableDomain("a.b.c.example.org"), "example.org");
});

test("a bundled multi-part ending keeps three labels", () => {
  assert.equal(registrableDomain("www.bbc.co.uk"), "bbc.co.uk");
  assert.equal(registrableDomain("iplayer.bbc.co.uk"), "bbc.co.uk");
  assert.equal(registrableDomain("cdn.example.com.au"), "example.com.au");
  assert.equal(registrableDomain("video.example.co.jp"), "example.co.jp");
});

// The table is ~30 common endings, not the 10k-entry Public Suffix List, so it
// is approximate by construction. Two distinct GitHub Pages sites merging into
// one row is the known, accepted imprecision.
test("an ending outside the table degrades to the last two labels", () => {
  assert.equal(registrableDomain("aryan.github.io"), "github.io");
});

test("a bare host, an IP address and an empty host survive", () => {
  assert.equal(registrableDomain("localhost"), "localhost");
  assert.equal(registrableDomain("127.0.0.1"), "127.0.0.1");
  assert.equal(registrableDomain(""), "");
});

test("the Service of a site with no Adapter is its registrable domain", () => {
  assert.equal(serviceFor("https://www.youtube.com/watch?v=abc"), "youtube.com");
  assert.equal(serviceFor("https://music.youtube.com/watch?v=abc"), "youtube.com");
  assert.equal(serviceFor("https://cdn.example.co.uk/v/clip.mp4"), "example.co.uk");
  assert.equal(serviceFor("about:blank"), "unknown");
});
