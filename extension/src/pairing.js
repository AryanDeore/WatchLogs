// Pure pairing-string helpers. No `chrome.*`, no DOM — imported by both the
// service worker and the Node test suite.
//
// A pairing string is base64( JSON {host, port, token} ), produced by the App's
// Settings and pasted into the extension once (issue #26).

/**
 * @typedef {{ host: string, port: number, token: string }} Pairing
 */

/**
 * @param {string} input
 * @returns {Pairing}
 * @throws {Error} if the string is not base64, not a JSON object, or missing/invalid fields
 */
export function parsePairingString(input) {
  const trimmed = String(input ?? "").trim();
  if (trimmed === "") {
    throw new Error("pairing string is empty");
  }

  let decoded;
  try {
    decoded = atob(trimmed);
  } catch {
    throw new Error("pairing string is not valid base64");
  }

  let json;
  try {
    json = JSON.parse(decoded);
  } catch {
    throw new Error("pairing string is not JSON");
  }

  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new Error("pairing string is not an object");
  }

  const { host, port, token } = json;
  if (typeof host !== "string" || host === "") {
    throw new Error("pairing string is missing host");
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("pairing string has an invalid port");
  }
  if (typeof token !== "string" || token === "") {
    throw new Error("pairing string is missing token");
  }
  return { host, port, token };
}

/**
 * @param {Pairing} pairing
 * @returns {string}
 */
export function encodePairingString({ host, port, token }) {
  return btoa(JSON.stringify({ host, port, token }));
}

/**
 * @param {Pick<Pairing, "host" | "port">} pairing
 * @returns {string} e.g. "http://127.0.0.1:48920"
 */
export function baseUrl({ host, port }) {
  return `http://${host}:${port}`;
}
