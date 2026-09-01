// The two ids the Extension mints. Both have to work on a plain `http://` page,
// which rules out `crypto.randomUUID` and `crypto.subtle` — neither exists
// outside a secure context, and plenty of video still lives on http.

import test from "node:test";
import assert from "node:assert/strict";
import { sha1Hex, uuidv4 } from "../src/ids.js";

test("sha1Hex matches the published vectors", () => {
  assert.equal(sha1Hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709");
  assert.equal(sha1Hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d");
  assert.equal(
    sha1Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
  );
  assert.equal(
    sha1Hex("The quick brown fox jumps over the lazy dog"),
    "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
  );
});

test("sha1Hex spans the block boundary correctly", () => {
  for (const length of [54, 55, 56, 63, 64, 65, 119, 120, 128]) {
    assert.match(sha1Hex("a".repeat(length)), /^[0-9a-f]{40}$/);
  }
  // 55 bytes is the last length whose padding still fits in one block.
  assert.equal(sha1Hex("a".repeat(55)), "c1c8bbdc22796e28c0e15163d20899b65621d65a");
  assert.equal(sha1Hex("a".repeat(56)), "c2db330f6083854c99d4b5bfb6e8f29f201be699");
});

test("sha1Hex is UTF-8, not UTF-16", () => {
  assert.equal(sha1Hex("é"), sha1Hex("é"));
  assert.match(sha1Hex("日本語"), /^[0-9a-f]{40}$/);
});

test("uuidv4 is a version-4 uuid and does not repeat", () => {
  const ids = new Set(Array.from({ length: 500 }, uuidv4));
  assert.equal(ids.size, 500);
  for (const id of ids) {
    assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  }
});
