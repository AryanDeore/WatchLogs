// Drives the real unpacked extension in a real Chromium, the way a user's
// browser would: `launchPersistentContext` + `--load-extension`, the
// background service worker reachable through `context.serviceWorkers()`,
// and `chrome.storage.local` seeded with a pairing string exactly like
// pasting one into Options would.
//
// Extensions only start their service worker in a *headed* persistent
// context here — `--headless=new` never fires the `serviceworker` event for
// an unpacked MV3 extension on the Chromium build Playwright ships, so this
// intentionally does not pass `headless: true`.

import { chromium } from "playwright";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";

const EXTENSION_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Fire a real `visibilitychange` at `page`'s own content-script world, with
 * `document.visibilityState`/`hidden` overridden first.
 *
 * There's no faking a real OS-level tab switch here — a background tab in
 * this Chromium reports the same `hasFocus()`/`visibilityState` as the
 * foreground one, headed or not, so `page.bringToFront()` on a second tab
 * doesn't actually hide the first. And overriding the property from the
 * page's normal (main-world) `page.evaluate` doesn't reach content.js either:
 * Chrome gives every content script its own isolated V8 world with its own
 * copy of `document`'s wrapper, so a main-world override is invisible to it.
 * This reaches into that same isolated world over CDP (`Runtime.evaluate`
 * against the execution context named after the extension, per
 * `chrome.runtime.getManifest().name`) and overrides it there, so content.js
 * reads exactly what a real hidden tab would hand it.
 */
export async function hidePage(context, page) {
  const cdp = await context.newCDPSession(page);
  const contexts = [];
  cdp.on("Runtime.executionContextCreated", (event) => contexts.push(event.context));
  await cdp.send("Runtime.enable");

  // A content script's isolated world is named after the extension (here,
  // manifest.json's `name`, "WatchLogs") and its own origin is the
  // extension's — not the page's — so match on name alone. This CDP session
  // is scoped to `page`, so nothing else can produce that name here.
  const deadline = Date.now() + 5_000;
  let world;
  while (!(world = contexts.find((c) => c.name === "WatchLogs"))) {
    if (Date.now() > deadline) throw new Error("hidePage: never saw the content script's isolated world");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  await cdp.send("Runtime.evaluate", {
    contextId: world.id,
    expression: `
      Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true });
      Object.defineProperty(document, "hidden", { value: true, configurable: true });
      document.dispatchEvent(new Event("visibilitychange"));
    `,
  });
  await cdp.detach();
}

/**
 * @returns {Promise<{
 *   context: import("playwright").BrowserContext,
 *   extensionId: string,
 *   pair: (pairingString: string) => Promise<{ ok: boolean, error?: string }>,
 *   forceFlush: () => Promise<void>,
 *   close: () => Promise<void>,
 * }>}
 */
export async function launchExtension() {
  const userDataDir = await mkdtemp(path.join(tmpdir(), "watchlogs-e2e-"));
  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
    ],
  });

  let worker = context.serviceWorkers()[0];
  if (!worker) worker = await context.waitForEvent("serviceworker", { timeout: 15_000 });
  const extensionId = new URL(worker.url()).hostname;

  // A blank, always-open extension page to run privileged `chrome.*` calls
  // from — anything under the extension's origin can reach `chrome.storage`
  // and `chrome.runtime.sendMessage`, and options.html is the lightest one
  // that's already part of the extension.
  const control = await context.newPage();
  await control.goto(`chrome-extension://${extensionId}/options.html`);

  return {
    context,
    extensionId,
    pair: (pairingString) =>
      control.evaluate(
        (ps) => chrome.runtime.sendMessage({ type: "pair", pairingString: ps }),
        pairingString,
      ),
    forceFlush: () => control.evaluate(() => chrome.runtime.sendMessage({ type: "flush" })),
    async close() {
      await context.close();
      await rm(userDataDir, { recursive: true, force: true });
    },
  };
}
