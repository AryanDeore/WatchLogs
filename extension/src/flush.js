// Pure Flush helpers. No `chrome.*`, no DOM — imported by both the service
// worker and the Node test suite.

export const SCHEMA_VERSION = 1;

/**
 * @typedef {{ extInstanceId: string, extVersion: string, browser: string, os: string }} Agent
 */

/**
 * Build a heartbeat Flush envelope: a valid Flush whose `views` array is empty
 * (schema v1, `prototypes/message-schema/SCHEMA.md`).
 *
 * @param {{ flushId: string, sentAt: number, agent: Agent }} params
 */
export function buildHeartbeat({ flushId, sentAt, agent }) {
  return {
    schemaVersion: SCHEMA_VERSION,
    flushId,
    sentAt,
    agent,
    views: [],
  };
}

/**
 * Is `ack` a well-formed Ack `{flushId, accepted:true, views:[], serverTime}`
 * for the Flush we just sent?
 *
 * @param {unknown} ack
 * @param {string} expectedFlushId
 * @returns {boolean}
 */
export function isWellFormedAck(ack, expectedFlushId) {
  return (
    typeof ack === "object" &&
    ack !== null &&
    ack.flushId === expectedFlushId &&
    ack.accepted === true &&
    Array.isArray(ack.views) &&
    Number.isFinite(ack.serverTime)
  );
}

/**
 * @typedef {(
 *   | { outcome: "accepted", ack: object }
 *   | { outcome: "re-pair" }
 *   | { outcome: "retry", reason: string }
 * )} FlushDecision
 */

/**
 * Map a `POST /v1/flush` result onto what the extension should do. Issue #26
 * defines only two outcomes for the extension — a `200` with a valid Ack, and a
 * `401` — so everything else (a lost response, any other status, a `200` whose
 * body isn't a valid Ack) is "keep the heartbeat cadence and try again".
 *
 * @param {number} status  HTTP status, or 0 if the request never completed
 * @param {unknown} body   parsed JSON body, or null
 * @param {string} expectedFlushId
 * @returns {FlushDecision}
 */
export function interpretFlushResponse(status, body, expectedFlushId) {
  if (status === 200) {
    return isWellFormedAck(body, expectedFlushId)
      ? { outcome: "accepted", ack: body }
      : { outcome: "retry", reason: "malformed-ack" };
  }
  if (status === 401) {
    return { outcome: "re-pair" };
  }
  return { outcome: "retry", reason: status === 0 ? "no-response" : `status-${status}` };
}
