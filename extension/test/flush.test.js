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

test("buildHeartbeat produces a schema-v1 envelope with empty views", () => {
  const body = buildHeartbeat({ flushId: "f-1", sentAt: 1700000000000, agent });
  assert.equal(body.schemaVersion, SCHEMA_VERSION);
  assert.equal(body.flushId, "f-1");
  assert.equal(body.sentAt, 1700000000000);
  assert.deepEqual(body.agent, agent);
  assert.deepEqual(body.views, []);
});

test("interpretFlushResponse maps statuses to actions", () => {
  assert.equal(interpretFlushResponse(200, { accepted: true }).outcome, "accepted");
  assert.equal(interpretFlushResponse(400, null).outcome, "drop");
  assert.equal(interpretFlushResponse(401, null).outcome, "re-pair");
  assert.equal(interpretFlushResponse(415, { error: "schemaVersion" }).outcome, "keep-buffered");
  assert.equal(interpretFlushResponse(413, null).outcome, "retry");
  assert.equal(interpretFlushResponse(500, null).outcome, "retry");
  assert.equal(interpretFlushResponse(0, null).outcome, "retry");
});

test("isWellFormedAck checks flushId, accepted, views, serverTime", () => {
  const ack = { flushId: "f-1", accepted: true, views: [], serverTime: 1700000000004 };
  assert.equal(isWellFormedAck(ack, "f-1"), true);
  assert.equal(isWellFormedAck(ack, "other"), false);
  assert.equal(isWellFormedAck({ ...ack, accepted: false }, "f-1"), false);
  assert.equal(isWellFormedAck({ ...ack, views: undefined }, "f-1"), false);
  assert.equal(isWellFormedAck(null, "f-1"), false);
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

test("a lost response moves state to disconnected", () => {
  const next = reduce({ status: "connected", lastFlushAt: 0 }, { outcome: "retry" }, 9000);
  assert.equal(next.status, "disconnected");
  assert.match(summarize(next, 9000), /Disconnected/);
});

test("the initial state reads as not paired", () => {
  assert.match(summarize(INITIAL_STATE, 0), /Not paired/);
});
