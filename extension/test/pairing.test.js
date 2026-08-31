import test from "node:test";
import assert from "node:assert/strict";
import {
  parsePairingString,
  encodePairingString,
  baseUrl,
} from "../src/pairing.js";

test("round-trips {host, port, token}", () => {
  const pairing = { host: "127.0.0.1", port: 48920, token: "dG9rZW4tYnl0ZXM=" };
  assert.deepEqual(parsePairingString(encodePairingString(pairing)), pairing);
});

test("tolerates surrounding whitespace", () => {
  const encoded = encodePairingString({ host: "127.0.0.1", port: 1, token: "t" });
  assert.deepEqual(parsePairingString(`\n  ${encoded}  \n`), {
    host: "127.0.0.1",
    port: 1,
    token: "t",
  });
});

test("rejects an empty string", () => {
  assert.throws(() => parsePairingString("   "), /empty/);
});

test("rejects non-base64", () => {
  assert.throws(() => parsePairingString("@@@ not base64 @@@"), /base64/);
});

test("rejects base64 that is not JSON", () => {
  assert.throws(() => parsePairingString(btoa("hello world")), /not JSON/);
});

test("rejects a JSON array", () => {
  assert.throws(() => parsePairingString(btoa("[1,2,3]")), /not an object/);
});

test("rejects a missing token", () => {
  assert.throws(
    () => parsePairingString(btoa(JSON.stringify({ host: "h", port: 5 }))),
    /missing token/,
  );
});

test("rejects a missing host", () => {
  assert.throws(
    () => parsePairingString(btoa(JSON.stringify({ port: 5, token: "t" }))),
    /missing host/,
  );
});

test("rejects a fractional port", () => {
  assert.throws(
    () => parsePairingString(btoa(JSON.stringify({ host: "h", port: 80.5, token: "t" }))),
    /invalid port/,
  );
});

test("rejects an out-of-range port", () => {
  assert.throws(
    () => parsePairingString(btoa(JSON.stringify({ host: "h", port: 99999, token: "t" }))),
    /invalid port/,
  );
});

test("baseUrl builds a loopback origin", () => {
  assert.equal(baseUrl({ host: "127.0.0.1", port: 48920 }), "http://127.0.0.1:48920");
});
