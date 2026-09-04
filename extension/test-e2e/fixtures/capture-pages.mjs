// Re-captures the saved Service pages the Adapter suites run against.
//
// A YouTube watch page arrives as a near-empty shell plus a megabyte of JSON;
// the title and channel name only exist once the page's own scripts have built
// them. So this loads each URL in a real Chromium, waits for the DOM the
// Adapter reads to actually exist, and only then dumps it — the post-hydration
// HTML, which is what the Adapter meets in the wild.
//
// The scripts are stripped on the way out. They are most of the bytes, the
// Adapters never read them, and leaving them in would mean a fixture that
// re-hydrates (and so silently repairs itself) when a test loads it.
//
//   node test-e2e/fixtures/capture-pages.mjs            # all of them
//   node test-e2e/fixtures/capture-pages.mjs watch      # just one
//
// Needs the network. Netflix is not here and cannot be: a watch page needs a
// logged-in subscriber session, so `pages/netflix/*.html` are hand-built from
// the shipped player's DOM shape and say so at the top of each file.

import { chromium } from "playwright";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OUT_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "pages", "youtube");

/** `waitFor` is the DOM the Adapter needs; without it the dump is a shell. */
const PAGES = [
  { name: "watch", url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", waitFor: "#above-the-fold h1" },
  { name: "live", url: "https://www.youtube.com/live/jfKfPfyJRdk", waitFor: "#above-the-fold h1" },
  // An embed builds its title bar only once playback starts, so this one has to
  // be muted-autoplayed or the dump is an empty shell.
  { name: "embed", url: "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1&mute=1", waitFor: ".ytp-title-link" },
  { name: "shorts", url: "https://www.youtube.com/shorts/", waitFor: "ytd-reel-video-renderer" },
  { name: "channel", url: "https://www.youtube.com/@RickAstleyYT", waitFor: "ytd-browse" },
  { name: "music", url: "https://music.youtube.com/watch?v=dQw4w9WgXcQ", waitFor: "body" },
];

const wanted = process.argv.slice(2);
const pages = wanted.length ? PAGES.filter((page) => wanted.includes(page.name)) : PAGES;

const browser = await chromium.launch();
const context = await browser.newContext({ locale: "en-US", viewport: { width: 1280, height: 800 } });

for (const page of pages) {
  const tab = await context.newPage();
  try {
    await tab.goto(page.url, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await tab.waitForSelector(page.waitFor, { timeout: 30_000 }).catch(() => {
      console.warn(`  ! ${page.name}: never saw ${page.waitFor}; dumping anyway`);
    });
    // The last of the metadata lands a beat after the element it lands in.
    await tab.waitForTimeout(2500);

    const url = tab.url();
    const html = await tab.evaluate(() => {
      for (const script of document.querySelectorAll("script, link[rel=preload], noscript")) script.remove();
      return document.documentElement.outerHTML;
    });

    const header = `<!--\n  Captured ${new Date().toISOString().slice(0, 10)} from ${url}\n  by test-e2e/fixtures/capture-pages.mjs. Scripts stripped. Do not hand-edit —\n  re-capture instead, and expect the Adapter selectors to need a look.\n-->\n`;
    const file = path.join(OUT_DIR, `${page.name}.html`);
    await writeFile(file, header + html);
    console.log(`  ✓ ${page.name}  ${(html.length / 1024).toFixed(0)} KiB  ${url}`);
  } catch (error) {
    console.error(`  ✗ ${page.name}: ${error.message}`);
  } finally {
    await tab.close();
  }
}

await browser.close();
