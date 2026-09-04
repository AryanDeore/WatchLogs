// The few things every Adapter does the same way.
//
// Adapters are the only modules in the Extension that touch a page, and they
// take the page they touch as an argument — `{ location, document }` — rather
// than reaching for globals. That is what lets one be pointed at a saved
// YouTube page in a test, and what keeps "which selector" separate from "which
// source wins", which lives in `metadata.js`.

/**
 * The first of these selectors with text in it, or undefined.
 *
 * A selector matching an element that happens to be empty is not an answer: a
 * YouTube Short has the watch page's `<h1>` sitting in it, blank, and taking
 * that would report a Short with no title as confidently titled "".
 */
export function firstText(document, selectors) {
  for (const selector of selectors) {
    const text = document.querySelector(selector)?.textContent?.trim();
    if (text) return text;
  }
  return undefined;
}

/**
 * `high` only when the id came from a URL shape the Adapter recognises *and* it
 * found a non-empty title. Anything less is `low`, which costs the Adapter
 * `title` and `author` to mediaSession but never the id or the format — a
 * shaky id still beats no id.
 *
 * One rule, applied identically by every Adapter, so "how sure is it" can't
 * come to mean different things on different sites.
 */
export function confidenceOf(videoId, title) {
  return videoId && title ? "high" : "low";
}

/**
 * Call `cb` when the page's title changes.
 *
 * This is every Adapter's `onChange`, and it is deliberately the cheapest
 * possible watcher. Watching the specific elements an Adapter reads — the
 * heading, the channel link — would be more precise and would break silently
 * the next time YouTube reshuffles its DOM. A new video id does not need this
 * at all: a new video fires the player's own `loadedmetadata`, and the helper
 * already re-reads on every media event. This exists for the second-long
 * flicker where the id is already right and the title has not caught up.
 *
 * @returns {() => void} stop watching
 */
export function observeTitle(document, cb) {
  const head = document.querySelector("title")?.parentNode ?? document.head;
  if (!head || typeof MutationObserver !== "function") return () => {};
  // Observing the `<title>` element itself misses the case where the page
  // replaces the whole element rather than its text, so watch its parent.
  const observer = new MutationObserver(cb);
  observer.observe(head, { subtree: true, childList: true, characterData: true });
  return () => observer.disconnect();
}
