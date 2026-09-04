// Which Adapter, if any, this frame gets — decided once, at bind time.

import test from "node:test";
import assert from "node:assert/strict";
import { ADAPTERS, bindAdapter, buildHostMap } from "../src/adapters/router.js";
import { fakeDocument } from "./helpers/fake-document.js";

function bind(href, elements = {}) {
  return bindAdapter({ location: new URL(href), document: fakeDocument(elements) });
}

test("the shipped set is closed, ordered, and names itself", () => {
  assert.deepEqual(ADAPTERS.map((adapter) => adapter.id), ["youtube", "netflix"]);
});

test("the host map is built once and keyed by the suffix each Adapter claims", () => {
  const map = buildHostMap(ADAPTERS);
  assert.equal(map.get("youtube.com").id, "youtube");
  assert.equal(map.get("youtube-nocookie.com").id, "youtube");
  assert.equal(map.get("netflix.com").id, "netflix");
  assert.equal(map.get("com"), undefined);
});

test("a subdomain finds the Adapter its parent claimed", () => {
  assert.equal(bind("https://www.youtube.com/watch?v=abc").adapterId, "youtube");
  assert.equal(bind("https://m.youtube.com/watch?v=abc").adapterId, "youtube");
  assert.equal(bind("https://www.netflix.com/watch/81234567").adapterId, "netflix");
});

test("the router names the Service, and the Adapter's name is the short one", () => {
  const bound = bind("https://www.youtube.com/watch?v=abc");
  assert.equal(bound.service, "youtube");
  assert.equal(bound.adapterId, "youtube");
});

test("a site nobody claimed gets no Adapter and its own domain as the Service", () => {
  const bound = bind("https://www.bbc.co.uk/iplayer/episode/m001");
  assert.equal(bound.adapter, null);
  assert.equal(bound.adapterId, null);
  assert.equal(bound.service, "bbc.co.uk");
});

// The veto is the point of `matches`: the host matched, and the Adapter looked
// at the URL and said this is not a page it can read.
test("an Adapter that steps aside leaves the frame to the generic fallback", () => {
  for (const [url, service] of [
    ["https://www.youtube.com/@RickAstleyYT", "youtube.com"],
    ["https://music.youtube.com/watch?v=abc", "youtube.com"],
    ["https://www.netflix.com/browse", "netflix.com"],
  ]) {
    const bound = bind(url);
    assert.equal(bound.adapter, null, url);
    assert.equal(bound.adapterId, null, url);
    assert.equal(bound.service, service, url);
  }
});

test("what comes back is a live object, already pointed at this page", () => {
  const bound = bind("https://www.youtube.com/watch?v=dQw4w9WgXcQ", {
    "#above-the-fold h1": "Never Gonna Give You Up",
  });
  assert.equal(bound.adapter.read().videoId, "dQw4w9WgXcQ");
  assert.equal(typeof bound.adapter.onChange, "function");
});

// Cost is the number of labels in the hostname, not the number of Adapters:
// a 40-Short binge is one lookup, and a tenth Adapter would not slow it down.
test("the walk is most-specific-first and stops at the first hit", () => {
  const seen = [];
  const map = new Map([["b.example.com", { id: "specific" }], ["example.com", { id: "general" }]]);
  const spy = { get: (key) => (seen.push(key), map.get(key)) };
  const { walkHost } = bindAdapter;
  assert.equal(walkHost("a.b.example.com", spy).id, "specific");
  assert.deepEqual(seen, ["a.b.example.com", "b.example.com"]);
});
