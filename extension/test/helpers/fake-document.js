// A document that knows exactly one thing: which selector returns which text.
//
// The Adapters walk a list of single selectors and take the first with
// non-empty text, so a map from selector string to text is the whole of what
// they can observe. Enough to pin the ranking and the URL reading; the
// selectors themselves are pinned against real saved pages in the e2e suite.

/**
 * @param {Record<string, string|{content: string}>} elements  selector -> its
 *   text, or `{ content }` for a `<meta>`-style element read by attribute
 * @param {{ title?: string }} [page]
 */
export function fakeDocument(elements = {}, { title = "" } = {}) {
  return {
    title,
    querySelector(selector) {
      if (!(selector in elements)) return null;
      const value = elements[selector];
      if (typeof value === "string") return { textContent: value, getAttribute: () => null };
      return { textContent: "", getAttribute: (name) => value[name] ?? null };
    },
  };
}
