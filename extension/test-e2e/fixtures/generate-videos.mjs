// Regenerates the two committed video fixtures the e2e suite plays. Not run
// by the suite itself — a one-off, like `scripts/sample-flush.mjs`.
//
// No real media asset is checked out from anywhere: both fixtures come from
// recording a plain canvas animation through `MediaRecorder` in a headless
// tab, which is enough to give Chromium something it will actually decode and
// advance `currentTime` on.
//
//   - `short.webm`, one file, 8s: the positive control, and every other test
//     that just needs a player that really plays but doesn't need much runway.
//   - `medium.webm`, one file, 30s: tests that need to survive past one or two
//     5s sample ticks — a rate change, a hidden tab — without the video
//     ending mid-test.
//   - `stall-chunks.json`, an array of ~1s WebM segments: the stall/recovery
//     test appends these to a `MediaSource` by hand with a deliberate gap, so
//     the "network never sends another byte" stall is exact and repeatable
//     instead of racing real socket timing.
//
// Run: node test-e2e/fixtures/generate-videos.mjs

import { chromium } from "playwright";
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

async function withRecordingPage(fn) {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.setContent("<canvas id='c' width='64' height='64'></canvas>");
    return await fn(page);
  } finally {
    await browser.close();
  }
}

/** One combined WebM blob, `durationMs` long. */
async function recordSingle(durationMs) {
  const base64 = await withRecordingPage((page) =>
    page.evaluate(async (ms) => {
      const toBase64 = (bytes) => {
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        return btoa(binary);
      };
      const canvas = document.getElementById("c");
      const ctx = canvas.getContext("2d");
      const stream = canvas.captureStream(10);
      const chunks = [];
      const recorder = new MediaRecorder(stream, { mimeType: "video/webm;codecs=vp8" });
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) chunks.push(event.data);
      };
      const stopped = new Promise((resolve) => (recorder.onstop = resolve));
      recorder.start();
      let hue = 0;
      const tick = setInterval(() => {
        hue = (hue + 5) % 360;
        ctx.fillStyle = `hsl(${hue}, 80%, 50%)`;
        ctx.fillRect(0, 0, 64, 64);
      }, 100);
      ctx.fillRect(0, 0, 64, 64);
      await new Promise((resolve) => setTimeout(resolve, ms));
      clearInterval(tick);
      recorder.stop();
      await stopped;
      const buffer = await new Blob(chunks, { type: "video/webm" }).arrayBuffer();
      return toBase64(new Uint8Array(buffer));
    }, durationMs),
  );
  return Buffer.from(base64, "base64");
}

/** An array of ~1s WebM segment blobs, MSE-appendable in order. */
async function recordChunks(durationMs) {
  return withRecordingPage((page) =>
    page.evaluate(async (ms) => {
      const toBase64 = (bytes) => {
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        return btoa(binary);
      };
      const canvas = document.getElementById("c");
      const ctx = canvas.getContext("2d");
      const stream = canvas.captureStream(10);
      const chunksB64 = [];
      const recorder = new MediaRecorder(stream, { mimeType: "video/webm;codecs=vp8" });
      recorder.ondataavailable = async (event) => {
        if (event.data.size === 0) return;
        const buffer = await event.data.arrayBuffer();
        chunksB64.push(toBase64(new Uint8Array(buffer)));
      };
      const stopped = new Promise((resolve) => (recorder.onstop = resolve));
      recorder.start(1000); // 1s timeslices -> one MSE-appendable segment each
      let hue = 0;
      const tick = setInterval(() => {
        hue = (hue + 5) % 360;
        ctx.fillStyle = `hsl(${hue}, 80%, 50%)`;
        ctx.fillRect(0, 0, 64, 64);
      }, 100);
      await new Promise((resolve) => setTimeout(resolve, ms));
      clearInterval(tick);
      recorder.stop();
      await stopped;
      return chunksB64;
    }, durationMs),
  );
}

const short = await recordSingle(8000);
writeFileSync(path.join(here, "short.webm"), short);
console.log(`short.webm: ${short.length} bytes`);

const medium = await recordSingle(30000);
writeFileSync(path.join(here, "medium.webm"), medium);
console.log(`medium.webm: ${medium.length} bytes`);

const stallChunks = await recordChunks(20000);
writeFileSync(path.join(here, "stall-chunks.json"), JSON.stringify(stallChunks));
console.log(`stall-chunks.json: ${stallChunks.length} chunks`);
