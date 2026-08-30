// The single connection-state value the popup and menubar-equivalent read.
// Pure reducer over "what just happened"; storage I/O lives in background.js.

/**
 * @typedef {(
 *   | { status: "needs-pairing", reason?: string, at?: number }
 *   | { status: "connected", lastFlushAt: number, serverTime?: number }
 *   | { status: "disconnected", reason?: string, at?: number }
 * )} ConnectionState
 */

/** @type {ConnectionState} */
export const INITIAL_STATE = { status: "needs-pairing" };

/**
 * @param {ConnectionState} _previous
 * @param {import("./flush.js").FlushDecision} decision
 * @param {number} now  epoch ms
 * @returns {ConnectionState}
 */
export function reduce(_previous, decision, now) {
  switch (decision.outcome) {
    case "accepted":
      return {
        status: "connected",
        lastFlushAt: now,
        serverTime: isRecord(decision.ack) ? Number(decision.ack.serverTime) : undefined,
      };
    case "re-pair":
      return { status: "needs-pairing", reason: "unauthorized", at: now };
    case "keep-buffered":
      return { status: "disconnected", reason: "schemaVersion", at: now };
    case "drop":
      return { status: "disconnected", reason: "rejected", at: now };
    default:
      return { status: "disconnected", reason: "no-response", at: now };
  }
}

/**
 * One-line summary, the extension's echo of the App's menubar status line.
 * @param {ConnectionState} state
 * @param {number} now
 */
export function summarize(state, now) {
  switch (state.status) {
    case "needs-pairing":
      return state.reason === "unauthorized"
        ? "Re-pair needed — the token was rejected"
        : "Not paired — paste a pairing string in Options";
    case "connected": {
      const seconds = Math.max(0, Math.floor((now - state.lastFlushAt) / 1000));
      return `Connected · last flush ${seconds}s ago`;
    }
    default:
      return "Disconnected — the App isn't answering";
  }
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}
