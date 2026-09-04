// content.js has no unit-test seam: it needs a real DOM and a real chrome.*,
// which node --test does not provide. This suite drives the actual unpacked
// extension in a real Chromium instead — the page helper, the buffer, the
// worker and a stub App, wired exactly like a real browser run except that
// the App is this file's `stub-server.mjs`, so nothing here ever touches
// `~/Library/Application Support/WatchLogs/watchlogs.sqlite`.
//
// One browser context and one stub server are shared across the whole file
// (a fresh extension load costs a couple of seconds); each test gets its own
// tab and tags its fixture page's URL so its Views are unmistakable in the
// server's growing `flushes` log.
//
// Run with `npm run test:e2e` — kept out of `npm test` because it needs a
// real Chromium download and takes tens of seconds, not the sub-second
// budget of the pure-module suite.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { startStubServer } from "./stub-server.mjs";
import { launchExtension, hidePage } from "./extension.mjs";
import { uniqueTag, taggedUrl, viewsTagged, eventsTagged, viewsSince, waitUntil } from "./helpers.mjs";

let server;
let ext;

before(async () => {
  server = await startStubServer();
  ext = await launchExtension();
  const result = await ext.pair(server.pairingString);
  assert.equal(result.ok, true, `pairing the stub App failed: ${result.error}`);
});

after(async () => {
  await ext?.close();
  await server?.close();
});

test(
  "a really-playing video yields mediaFound / play / sample with pos advancing and playing:true",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/player.html", tag, { src: "/fixtures/short.webm" }));
      await page.evaluate(() => document.getElementById("v").play());

      await waitUntil(() => eventsTagged(server, tag).some((event) => event.type === "sample"), {
        timeoutMs: 15_000,
        message: "expected a sample event",
      });

      const events = eventsTagged(server, tag);
      assert.deepEqual(events.slice(0, 2).map((event) => event.type), ["mediaFound", "play"]);
      const sample = events.find((event) => event.type === "sample");
      assert.equal(sample.playing, true);
      assert.ok(sample.pos > 0, `expected pos to have advanced, got ${sample.pos}`);
    } finally {
      await page.close();
    }
  },
);

test(
  "a player held at paused === false, readyState === 0 yields no sample claiming playing:true",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      // /phantom.mp4 sends headers and then never answers again — the CDN
      // that never resolved, from the phantom-time bug. play()'s own promise
      // never settles either in that state, so fire it and move on rather
      // than awaiting it.
      await page.goto(taggedUrl(server, "/player.html", tag, { src: "/phantom.mp4" }));
      await page.evaluate(() => {
        document.getElementById("v").play().catch(() => {});
      });

      // Longer than one 5s heartbeat: proof the timer never started, not
      // just that we got unlucky with when we looked.
      await new Promise((resolve) => setTimeout(resolve, 11_000));

      // Nothing here calls persistAll(flush: true) on its own — a stuck
      // player never re-arms the timer that would — so ask the worker
      // directly for whatever made it to the buffer.
      await ext.forceFlush();
      await waitUntil(() => viewsTagged(server, tag).length > 0, {
        timeoutMs: 10_000,
        message: "expected the phantom View to appear in a Flush",
      });

      const events = eventsTagged(server, tag);
      assert.ok(
        !events.some((event) => event.type === "sample"),
        `expected no sample events, got ${JSON.stringify(events)}`,
      );
    } finally {
      await page.close();
    }
  },
);

test(
  "a stall mid-playback stops the clock, and the playing event on recovery restarts it",
  { timeout: 40_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/stall.html", tag));
      // 4 of ~18 one-second segments: enough to start playing, not enough to
      // outrun the first 5s tick.
      await page.evaluate((n) => window.wlArmStall(n), 4);

      const firstSample = await waitUntil(
        () => eventsTagged(server, tag).find((event) => event.type === "sample"),
        { timeoutMs: 15_000, message: "expected the stall-catching sample" },
      );
      assert.equal(firstSample.playing, false, "the tick during the stall should report playing:false");

      // The timer should now be cleared: waiting through what would have
      // been the next tick must not produce a second sample.
      await new Promise((resolve) => setTimeout(resolve, 4_000));
      assert.equal(
        eventsTagged(server, tag).filter((event) => event.type === "sample").length,
        1,
        "expected the clock to have stopped, not ticked again while still stalled",
      );

      await page.evaluate(() => window.wlResumeStall());

      await waitUntil(
        () => eventsTagged(server, tag).filter((event) => event.type === "sample").length >= 2,
        { timeoutMs: 15_000, message: "expected recovery to re-arm the timer" },
      );
      const samples = eventsTagged(server, tag).filter((event) => event.type === "sample");
      assert.equal(samples.at(-1).playing, true, "the tick after recovery should report playing:true");
    } finally {
      await page.close();
    }
  },
);

test("a frame whose URL has no host still sends a non-empty service", { timeout: 30_000 }, async () => {
  const page = await ext.context.newPage();
  const since = server.flushes.length;
  try {
    await page.goto(`${server.baseUrl}/hostless.html`);
    // hostless.html injects a <video> into an about:blank iframe once it
    // loads; wait for it, then play it the same way a real page would.
    await page.waitForFunction(() => document.getElementById("f")?.contentDocument?.getElementById("v"));
    await page.evaluate(() => document.getElementById("f").contentDocument.getElementById("v").play());

    const view = await waitUntil(
      () => viewsSince(server, since, (v) => v.embedded === true)[0],
      { timeoutMs: 15_000, message: "expected the hostless frame's View" },
    );

    assert.notEqual(view.service, "", "service must never be empty on the wire");
    assert.equal(view.service, "unknown");
  } finally {
    await page.close();
  }
});

test("a hidden tab reports visible:false, and the wire never says background", { timeout: 30_000 }, async () => {
  const tag = uniqueTag();
  const page = await ext.context.newPage();
  try {
    await page.goto(taggedUrl(server, "/player.html", tag, { src: "/fixtures/medium.webm" }));
    await page.evaluate(() => document.getElementById("v").play());

    // The first sample, still foreground — the baseline `visible` flips against.
    await waitUntil(() => eventsTagged(server, tag).some((event) => event.type === "sample"), {
      timeoutMs: 15_000,
    });

    await hidePage(ext.context, page);

    const secondSample = await waitUntil(
      () => eventsTagged(server, tag).filter((event) => event.type === "sample").at(1),
      { timeoutMs: 15_000, message: "expected a sample after hiding" },
    );

    const events = eventsTagged(server, tag);
    assert.ok(events.some((event) => event.type === "hidden"), "expected a hidden event");
    assert.equal(secondSample.visible, false);
    assert.ok(!JSON.stringify(events).includes("background"), "the wire has no concept of background");
  } finally {
    await page.close();
  }
});

test("rate changes ride the wire without inflating the sample cadence", { timeout: 30_000 }, async () => {
  const tag = uniqueTag();
  const page = await ext.context.newPage();
  try {
    await page.goto(taggedUrl(server, "/player.html", tag, { src: "/fixtures/medium.webm" }));
    await page.evaluate(() => document.getElementById("v").play());
    await waitUntil(() => eventsTagged(server, tag).some((event) => event.type === "sample"), {
      timeoutMs: 15_000,
    });

    await page.evaluate(() => {
      document.getElementById("v").playbackRate = 2;
    });

    await waitUntil(
      () => eventsTagged(server, tag).filter((event) => event.type === "sample").length >= 2,
      { timeoutMs: 15_000, message: "expected a second sample after the rate change" },
    );

    const events = eventsTagged(server, tag);
    const rateEvent = events.find((event) => event.type === "ratechange");
    assert.equal(rateEvent.rate, 2);

    const samples = events.filter((event) => event.type === "sample");
    const deltaMs = samples[1].t - samples[0].t;
    // Wall-clock cadence, not media-time: 2x playback for 5 real seconds is
    // still one sample, ~5s after the last one — never ~2.5s.
    assert.ok(deltaMs > 4000 && deltaMs < 6500, `expected ~5000ms between samples, got ${deltaMs}ms`);
  } finally {
    await page.close();
  }
});

test("two players on one page are two Views, each with its own seq", { timeout: 30_000 }, async () => {
  const tag = uniqueTag();
  const page = await ext.context.newPage();
  try {
    await page.goto(taggedUrl(server, "/two-players.html", tag));
    await page.evaluate(() => {
      document.getElementById("v1").play();
      document.getElementById("v2").play();
    });

    await waitUntil(() => new Set(viewsTagged(server, tag).map((view) => view.viewId)).size >= 2, {
      timeoutMs: 15_000,
      message: "expected two distinct Views",
    });

    const events = eventsTagged(server, tag);
    const byView = new Map();
    for (const event of events) {
      if (!byView.has(event.viewId)) byView.set(event.viewId, []);
      byView.get(event.viewId).push(event);
    }

    assert.equal(byView.size, 2);
    for (const viewEvents of byView.values()) {
      assert.equal(viewEvents[0].type, "mediaFound");
      assert.equal(viewEvents[0].seq, 1, "each View counts its own seq from 1");
    }
  } finally {
    await page.close();
  }
});

test(
  "an ad slot that swaps its source on every loop stays one View, not one per loop",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/ad-slot.html", tag));
      await page.evaluate(() => {
        for (const el of document.querySelectorAll("video")) {
          el.playbackRate = 8; // an 8 s clip loops in ~1 s so the test stays fast
          el.play();
        }
      });

      await waitUntil(
        () => eventsTagged(server, tag).filter((event) => event.type === "ended").length >= 4,
        { timeoutMs: 25_000, message: "expected at least two loops on each of the two players" },
      );

      const events = eventsTagged(server, tag);
      assert.ok(
        !events.some((event) => event.type === "viewEnded"),
        "a loop that only swapped its source should never close a View",
      );

      const viewIds = new Set(viewsTagged(server, tag).map((view) => view.viewId));
      assert.equal(viewIds.size, 2, `expected exactly one View per player across every loop, got ${viewIds.size}`);
    } finally {
      await page.close();
    }
  },
);

test("a 1x1 video that actually plays yields no View at all", { timeout: 30_000 }, async () => {
  const tag = uniqueTag();
  const page = await ext.context.newPage();
  try {
    await page.goto(taggedUrl(server, "/pixel.html", tag));
    await page.evaluate(() => document.getElementById("v").play());

    // Long enough to have cleared a sample beat and opened a View, if it were
    // going to — the same margin the positive-control test at the top waits on.
    await page.waitForTimeout(6000);

    assert.equal(viewsTagged(server, tag).length, 0, "a 1x1 video should never open a View");
  } finally {
    await page.close();
  }
});

// --- Adapters, metadata and View boundaries (#24) ---------------------------------

test(
  "a burst of metadata changes lands as one metadataChange, and never carries a videoId",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/player.html", tag, { src: "/fixtures/medium.webm" }));
      await page.evaluate(() => document.getElementById("v").play());
      await waitUntil(() => eventsTagged(server, tag).some((event) => event.type === "sample"), {
        timeoutMs: 15_000,
        message: "expected the View to be open and reporting",
      });
      const before = eventsTagged(server, tag).filter((event) => event.type === "metadataChange").length;

      // The first second of a page load, in miniature: the title and the
      // now-playing block filling in one field at a time, faster than the
      // 500 ms wait.
      await page.evaluate(async () => {
        for (const step of ["Loading…", "Loading… |", "The Real Title"]) {
          document.title = step;
          navigator.mediaSession.metadata = new MediaMetadata({ title: step, artist: "The Author" });
          await new Promise((resolve) => setTimeout(resolve, 60));
        }
      });

      await waitUntil(
        () => eventsTagged(server, tag).filter((event) => event.type === "metadataChange").length > before,
        { timeoutMs: 15_000, message: "expected a metadataChange after the burst" },
      );
      // Long enough that a second, undebounced report would have arrived and
      // been Flushed by now.
      await page.waitForTimeout(7000);

      const reports = eventsTagged(server, tag).filter((event) => event.type === "metadataChange").slice(before);
      assert.equal(reports.length, 1, `expected one debounced report, got ${JSON.stringify(reports)}`);
      assert.equal(reports[0].changed.title, "The Real Title");
      assert.equal(reports[0].changed.author, "The Author");
      assert.equal("videoId" in reports[0].changed, false, "a new id is a View boundary, not a metadata change");
    } finally {
      await page.close();
    }
  },
);

test(
  "a livestream turning into its own replay is a metadataChange, not a new View",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/live.html", tag));
      await page.evaluate(() => window.wlStartBroadcast());

      await waitUntil(() => viewsTagged(server, tag).some((view) => view.contentFormat === "live"), {
        timeoutMs: 15_000,
        message: "expected the View to open as live",
      });
      const liveViewId = viewsTagged(server, tag).find((view) => view.contentFormat === "live").viewId;

      // The broadcast ends and the same URL becomes the replay of itself: same
      // video, finite length now.
      await page.evaluate(() => window.wlEndBroadcast());

      await waitUntil(
        () =>
          eventsTagged(server, tag).some(
            (event) => event.type === "metadataChange" && event.changed.contentFormat === "standard",
          ),
        { timeoutMs: 15_000, message: "expected a metadataChange carrying the new contentFormat" },
      );

      const viewIds = new Set(viewsTagged(server, tag).map((view) => view.viewId));
      assert.deepEqual([...viewIds], [liveViewId], "the same View carries on through a format change");
    } finally {
      await page.close();
    }
  },
);

test(
  "moving to the next video without a page load ends one View and starts the next",
  { timeout: 30_000 },
  async () => {
    const tag = uniqueTag();
    const page = await ext.context.newPage();
    try {
      await page.goto(taggedUrl(server, "/player.html", tag, { src: "/fixtures/medium.webm" }));
      await page.evaluate(() => document.getElementById("v").play());
      await waitUntil(() => eventsTagged(server, tag).some((event) => event.type === "sample"), {
        timeoutMs: 15_000,
        message: "expected the first View to be reporting",
      });
      const firstViewId = viewsTagged(server, tag)[0].viewId;

      // What a Short-to-Short swipe or a next-episode click looks like from
      // here: the address changes, the page does not reload, and nothing
      // re-routes.
      await page.evaluate(() => history.pushState({}, "", `/player.html/next${location.search}`));

      await waitUntil(() => viewsTagged(server, tag).some((view) => view.viewId !== firstViewId), {
        timeoutMs: 20_000,
        message: "expected a second View for the new address",
      });

      const second = viewsTagged(server, tag).find((view) => view.viewId !== firstViewId);
      assert.equal(second.previousViewId, firstViewId, "the new View names the one it replaced");
      assert.notEqual(second.videoId, viewsTagged(server, tag)[0].videoId);
      const ending = eventsTagged(server, tag).find(
        (event) => event.type === "viewEnded" && event.viewId === firstViewId,
      );
      assert.equal(ending.reason, "video-changed");
    } finally {
      await page.close();
    }
  },
);
