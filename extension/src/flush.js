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
 * @typedef {(
 *   | { outcome: "accepted", ack: unknown }
 *   | { outcome: "re-pair" }
 *   | { outcome: "keep-buffered" }
 *   | { outcome: "drop" }
 *   | { outcome: "retry" }
 * )} FlushDecision
 */

/**
 * Map an HTTP status from `POST /v1/flush` onto what the extension should do,
 * per the system spec's failure table (#20):
 *   200 accepted · 400 drop · 401 stop + re-pair · 413 split + retry ·
 *   415 keep buffered (App can't parse this schema) · else keep + retry.
 *
 * @param {number} status
 * @param {unknown} body  parsed JSON body, or null
 * @returns {FlushDecision}
 */
export function interpretFlushResponse(status, body) {
  switch (status) {
    case 200:
      return { outcome: "accepted", ack: body };
    case 400:
      return { outcome: "drop" };
    case 401:
      return { outcome: "re-pair" };
    case 415:
      return { outcome: "keep-buffered" };
    default:
      // 413 (would split a real batch; a heartbeat can't), 500, timeouts,
      // connection-refused — keep the batch and try again later.
      return { outcome: "retry" };
  }
}

/**
 * Validate the shape of an Ack `{flushId, accepted, views, serverTime}`.
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
