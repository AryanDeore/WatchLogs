// The generic fallback — the reader for every site nobody has written an
// Adapter for, which is almost all of them.
//
// It is not in the router's Adapter list: it is what a frame gets when nothing
// in that list wants the page, and it runs on Adapter frames too, underneath,
// as the bottom rung of every ranking in `metadata.js`. So this is written to
// always answer, never to fail: an unparseable URL still yields a Service, and
// a page with no metadata at all still yields the browser tab's title.
//
// It never reports better than `fallback` confidence, which is what puts a
// site in the app's "needs an Adapter" flag.

import {
  contentFormatFor,
  durationOf,
  identifyingSrc,
  normalizeUrl,
  serviceFor,
  videoIdSourceFor,
} from "../identify.js";

/** Where a page that isn't a Service puts its real title. */
const TITLE_META = ["meta[property='og:title']", "meta[name='twitter:title']"];

/** Best-effort only. Most sites say nothing here, and that is a fine answer. */
const AUTHOR_META = ["meta[name=author]", "meta[property='og:video:director']", "[itemprop=author]"];

/**
 * Everything the fallback can say about the video in this frame.
 *
 * @param {object} page
 * @param {{ href: string }} page.location
 * @param {Document} page.document
 * @param {string} [page.mediaSrc]  the element's own `currentSrc`
 * @param {number} [page.duration]  the element's `duration`
 * @param {boolean} [page.disambiguate]  fold the element's own source into the
 *   id — set only for the second and later players in one frame, so that a page
 *   showing two videos at once is two Views while the ordinary one-player page
 *   keeps the clean page-address id
 */
export function readGeneric({ location, document, mediaSrc = "", duration = NaN, disambiguate = false } = {}) {
  const href = location?.href ?? "";
  const pageId = videoIdSourceFor(href);
  const srcId = disambiguate ? identifyingSrc(mediaSrc) : null;

  return {
    service: serviceFor(href),
    // `url` keeps its query — it is the link a person would follow back to the
    // video, and the id's reasons for dropping the query are not its reasons.
    url: normalizeUrl(href),
    videoIdSource: srcId && srcId !== pageId ? `${pageId} ${srcId}` : pageId,
    contentFormat: contentFormatFor(duration),
    durationSec: durationOf(duration),
    ...maybe("title", firstMeta(document, TITLE_META)),
    ...maybe("author", firstMeta(document, AUTHOR_META)),
    // The last rung of the title ranking, kept separate from `og:title` so the
    // View can record which of the two it ended up with.
    ...maybe("documentTitle", document?.title || undefined),
    confidence: "fallback",
  };
}

/** The first of these `<meta>` tags with something in its `content`. */
function firstMeta(document, selectors) {
  for (const selector of selectors) {
    const content = document?.querySelector(selector)?.getAttribute("content")?.trim();
    if (content) return content;
  }
  return undefined;
}

/** A field the fallback could not fill is left off, not set to "". */
function maybe(field, value) {
  return value === undefined ? {} : { [field]: value };
}
