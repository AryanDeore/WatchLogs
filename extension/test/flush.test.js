import test from "node:test";
import assert from "node:assert/strict";
import {
  SCHEMA_VERSION,
  buildHeartbeat,
  interpretFlushResponse,
  isWellFormedAck,
} from "../src/flush.js";
import { INITIAL_STATE, reduce, summarize } from "../src/state.js";

const agent = {
  extInstanceId: "ext-1",
  extVersion: "0.1.0",
  browser: "chrome",
  os: "macOS",
};

const ackFor = (flushId) => ({
  flushId,
  accepted: true,
  views: [],
  serverTime: 1700000000004,
});

test("buildHeartbeat produces a schema-v1 envelope with empty views", () => {
  const body = buildHeartbeat({ flushId: "f-1", sentAt: 1700000000000, agent });
  assert.equal(body.schemaVersion, SCHEMA_VERSION);
  assert.equal(body.flushId, "f-1");
  assert.equal(body.sentAt, 1700000000000);
  assert.deepEqual(body.agent, agent);
  assert.deepEqual(body.views, []);
});

test("isWellFormedAck checks flushId, accepted, views, serverTime", () => {
  assert.equal(isWellFormedAck(ackFor("f-1"), "f-1"), true);
  assert.equal(isWellFormedAck(ackFor("f-1"), "other"), false);
  assert.equal(isWellFormedAck({ ...ackFor("f-1"), accepted: false }, "f-1"), false);
  assert.equal(isWellFormedAck({ ...ackFor("f-1"), views: undefined }, "f-1"), false);
  assert.equal(isWellFormedAck(null, "f-1"), false);
});

test("a 200 with a valid Ack is accepted", () => {
  const decision = interpretFlushResponse(200, ackFor("f-1"), "f-1");
  assert.equal(decision.outcome, "accepted");
  assert.equal(decision.ack.serverTime, 1700000000004);
});

test("a 200 whose body is not a valid Ack is a retry, not accepted", () => {
  assert.deepEqual(interpretFlushResponse(200, { hello: "world" }, "f-1"), {
    outcome: "retry",
    reason: "malformed-ack",
  });
  assert.deepEqual(interpretFlushResponse(200, ackFor("other-flush"), "f-1"), {
    outcome: "retry",
    reason: "malformed-ack",
  });
});

test("a 401 is re-pair", () => {
  assert.deepEqual(interpretFlushResponse(401, null, "f-1"), { outcome: "re-pair" });
});

test("any other status is a retry with the status in the reason", () => {
  assert.deepEqual(interpretFlushResponse(0, null, "f-1"), { outcome: "retry", reason: "no-response" });
  assert.deepEqual(interpretFlushResponse(415, null, "f-1"), { outcome: "retry", reason: "status-415" });
  assert.deepEqual(interpretFlushResponse(500, null, "f-1"), { outcome: "retry", reason: "status-500" });
});

test("an accepted Flush moves state to connected", () => {
  const next = reduce(INITIAL_STATE, { outcome: "accepted", ack: { serverTime: 42 } }, 1000);
  assert.equal(next.status, "connected");
  assert.equal(next.lastFlushAt, 1000);
  assert.equal(next.serverTime, 42);
  assert.equal(summarize(next, 4000), "Connected · last flush 3s ago");
});

test("a 401 moves state to needs-pairing with an unauthorized reason", () => {
  const next = reduce({ status: "connected", lastFlushAt: 0 }, { outcome: "re-pair" }, 5000);
  assert.deepEqual(next, { status: "needs-pairing", reason: "unauthorized", at: 5000 });
  assert.match(summarize(next, 6000), /Re-pair needed/);
});

test("a retry moves state to disconnected, carrying the reason", () => {
  const next = reduce({ status: "connected", lastFlushAt: 0 }, { outcome: "retry", reason: "status-500" }, 9000);
  assert.equal(next.status, "disconnected");
  assert.equal(next.reason, "status-500");
  assert.match(summarize(next, 9000), /Disconnected/);
});

test("the initial state reads as not paired", () => {
  assert.match(summarize(INITIAL_STATE, 0), /Not paired/);
});
