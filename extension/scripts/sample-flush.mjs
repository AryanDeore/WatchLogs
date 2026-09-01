#!/usr/bin/env node
// Print one Flush body, built by the real capture modules from a scripted watch:
// 21 s in the foreground, then the tab is hidden for 9 s, then the user
// navigates away.
//
// The output is committed as the App's cross-language fixture
// (`app/Tests/WatchLogsKitTests/Fixtures/extension-flush.json`) so the two
// halves of WatchLogs are tested against the same bytes. Regenerate with:
//
//   node scripts/sample-flush.mjs > ../app/Tests/WatchLogsKitTests/Fixtures/extension-flush.json
//
// `test/fixture.test.js` fails if the committed file and this script disagree.

import { apply, buildFlush, initCapture } from "../src/capture.js";
import { identify } from "../src/identify.js";
import { sha1Hex } from "../src/ids.js";

// Fixed clock and fixed ids: a fixture has to be byte-stable.
const T0 = 1_788_026_400_000; // 2026-08-29T18:00:00Z, the SCHEMA example's window
const VIEW_ID = "9f2a1c04-11d2-4a55-9b3e-6c1f0e8a7d40";
const FLUSH_ID = "f1e2d3c4-5b6a-4c7d-8e9f-0a1b2c3d4e5f";

const page = identify({
  frameUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
  isTopFrame: true,
  mediaSrc: "blob:https://www.youtube.com/9f2a1c04",
  duration: 213,
});

const session = initCapture(T0, { tabId: 41 });
apply(session, {
  type: "OPEN",
  at: T0,
  viewId: VIEW_ID,
  view: { ...page, videoId: `sha1:${sha1Hex(page.videoIdSource)}` },
});
apply(session, {
  type: "META",
  at: T0 + 500,
  changed: { title: "Never Gonna Give You Up", author: "Rick Astley", durationSec: 213 },
  metadataSource: "mediaSession",
});
apply(session, { type: "PLAY", at: T0 + 1000, pos: 0 });

for (let beat = 1; beat <= 4; beat += 1) {
  apply(session, {
    type: "SAMPLE",
    at: T0 + 1000 + beat * 5000,
    pos: beat * 5,
    playing: true,
    visible: true,
  });
}

apply(session, { type: "HIDE", at: T0 + 22_000, pos: 21 });
for (let beat = 5; beat <= 6; beat += 1) {
  apply(session, {
    type: "SAMPLE",
    at: T0 + 1000 + beat * 5000,
    pos: beat * 5,
    playing: true,
    visible: false,
  });
}
apply(session, { type: "VIEW_ENDED", at: T0 + 31_000, pos: 30, reason: "nav" });

const body = buildFlush(session, {
  flushId: FLUSH_ID,
  sentAt: T0 + 31_000,
  agent: {
    extInstanceId: "ext-inst-7f3a9c21",
    extVersion: "0.1.0",
    browser: "chrome",
    os: "macOS",
  },
});

process.stdout.write(`${JSON.stringify(body, null, 2)}\n`);
