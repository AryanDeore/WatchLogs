// Shared plumbing for the content.js suite: tagging each test's fixture page
// so its Views are unmistakable in the stub App's growing `flushes` array
// (tests share one browser context and one server for speed), and a poll
// loop for "wait until this became true" that doesn't need the server to know
// anything about what a test cares about.

/** A short id to fold into a fixture page's URL, so its Views are unmistakable. */
export function uniqueTag() {
  return Math.random().toString(36).slice(2, 10);
}

/** `path` on the stub server, tagged so its View's `url` field carries `tag`. */
export function taggedUrl(server, path, tag, params = {}) {
  const url = new URL(path, server.baseUrl);
  url.searchParams.set("tag", tag);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return url.href;
}

/** Every View across every Flush so far whose `url` carries `tag`. */
export function viewsTagged(server, tag) {
  return server.flushes.flatMap((flush) => flush.views).filter((view) => view.url.includes(`tag=${tag}`));
}

/** Every Event across every tagged View so far, each stamped with its viewId. */
export function eventsTagged(server, tag) {
  return viewsTagged(server, tag).flatMap((view) => view.events.map((event) => ({ ...event, viewId: view.viewId })));
}

/**
 * Every View out of the Flushes the server has received since `since` (an
 * index into `server.flushes`, taken before the test's own action) — for the
 * one case tagging can't reach: a View whose own `url` is `about:blank`.
 */
export function viewsSince(server, since, predicate) {
  return server.flushes.slice(since).flatMap((flush) => flush.views).filter(predicate);
}

/**
 * Poll `check` until it returns a truthy value, or fail after `timeoutMs`.
 *
 * @param {() => unknown} check
 * @param {{ timeoutMs?: number, intervalMs?: number, message?: string }} [opts]
 */
export async function waitUntil(check, { timeoutMs = 20_000, intervalMs = 200, message } = {}) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = check();
    if (value) return value;
    if (Date.now() >= deadline) {
      throw new Error(message ?? `waitUntil: condition never became true within ${timeoutMs}ms`);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}
