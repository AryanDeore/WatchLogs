// A stand-in for the App and a static file server for the fixture pages, in
// one process. Bound to 127.0.0.1 because that's the only host the
// extension's `host_permissions` lets its background worker fetch —
// `manifest.json` grants `http://127.0.0.1/*`, not `localhost`.
//
// Never touches `~/Library/Application Support/WatchLogs/watchlogs.sqlite`:
// this *is* the App, for the duration of one test.

import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { encodePairingString } from "../src/pairing.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const PAGES_DIR = path.join(here, "pages");
const FIXTURES_DIR = path.join(here, "fixtures");

const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".webm": "video/webm",
  ".json": "application/json",
};

/**
 * @returns {Promise<{
 *   baseUrl: string,
 *   pairingString: string,
 *   flushes: object[],
 *   close: () => Promise<void>,
 * }>}
 */
export async function startStubServer() {
  const flushes = [];

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");

    if (req.method === "GET" && url.pathname === "/v1/ping") {
      sendJson(res, 200, { contract: "v1" });
      return;
    }

    if (req.method === "POST" && url.pathname === "/v1/flush") {
      const body = await readJsonBody(req);
      flushes.push(body);
      sendJson(res, 200, ackFor(body));
      return;
    }

    if (req.method === "GET" && url.pathname === "/phantom.mp4") {
      // Headers only, then silence: the CDN-never-answers case that produced
      // the phantom-time bug. The response is intentionally never ended.
      res.writeHead(200, { "Content-Type": "video/mp4", "Content-Length": 999_999_999 });
      return;
    }

    if (req.method === "GET" && url.pathname.startsWith("/fixtures/")) {
      await serveFile(res, path.join(FIXTURES_DIR, url.pathname.slice("/fixtures/".length)));
      return;
    }

    const pagePath = url.pathname === "/" ? "/player.html" : url.pathname;
    await serveFile(res, path.join(PAGES_DIR, pagePath));
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;

  return {
    baseUrl,
    pairingString: encodePairingString({ host: "127.0.0.1", port, token: "e2e-test-token" }),
    flushes,
    close() {
      return new Promise((resolve) => server.close(resolve));
    },
  };
}

/** Ack every View's highest seq — the App accepting the whole batch. */
function ackFor(body) {
  return {
    flushId: body.flushId,
    accepted: true,
    views: body.views.map((view) => ({
      viewId: view.viewId,
      ackSeq: Math.max(0, ...view.events.map((event) => event.seq)),
    })),
    serverTime: body.sentAt + 1,
  };
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "null"));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

async function serveFile(res, filePath) {
  try {
    const data = await readFile(filePath);
    const type = CONTENT_TYPES[path.extname(filePath)] ?? "application/octet-stream";
    res.writeHead(200, { "Content-Type": type, "Content-Length": data.length });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
}
