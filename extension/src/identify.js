// Generic, best-effort identification. Pure: it is handed strings and numbers
// the page helper read off the page, never the page itself.
//
// This slice ships no per-Service Adapter, so a Service is a hostname and a
// video id is a hash of the normalised URL. Every function here is the fallback
// an Adapter will later override for the site it knows.

/** Query params that move without the video moving. */
const NON_IDENTIFYING_PARAMS = new Set([
  "t", "start", "time_continue", "autoplay", "mute", "loop", "controls",
  "list", "index", "playlist", "pp", "si", "feature", "app", "ref", "ref_src",
  "fbclid", "gclid", "igshid", "spm", "share", "shared", "source",
]);

/** The Service of a site with no Adapter: its bare hostname. */
export function serviceFor(url) {
  const parsed = parse(url);
  return parsed ? stripWww(parsed.hostname) : "unknown";
}

/**
 * The page URL with the noise taken off: no fragment, no tracking params, no
 * trailing slash. This is what rides the wire as the View's `url`, and — with
 * the host normalised too — what the video id is hashed from.
 */
export function normalizeUrl(url, { stripHostPrefix = false } = {}) {
  const parsed = parse(url);
  if (!parsed) return String(url ?? "");

  const params = [...parsed.searchParams.entries()]
    .filter(([name]) => !NON_IDENTIFYING_PARAMS.has(name) && !name.startsWith("utm_"))
    .sort(([a], [b]) => a.localeCompare(b));

  const query = new URLSearchParams(params).toString();
  const path = parsed.pathname.replace(/\/+$/, "") || "/";
  const host = stripHostPrefix ? stripWww(parsed.hostname) : parsed.hostname;
  return `${parsed.protocol}//${host}${path}${query ? `?${query}` : ""}`;
}

/** The string a video id is hashed from. `www.` is noise; the rest is not. */
function idSource(url) {
  return normalizeUrl(url, { stripHostPrefix: true });
}

/** A media source only identifies anything when it is a real, stable URL. */
function identifyingSrc(mediaSrc) {
  const parsed = parse(mediaSrc);
  return parsed && (parsed.protocol === "http:" || parsed.protocol === "https:")
    ? idSource(mediaSrc)
    : null;
}

/**
 * Is this player sitting in someone else's page? True for a cross-site iframe,
 * and for a frame whose ancestor we cannot read (which only happens when the
 * ancestor is a different origin).
 */
export function isEmbedded({ isTopFrame, frameUrl, topUrl }) {
  if (isTopFrame) return false;
  const frameHost = parse(frameUrl)?.hostname;
  const topHost = parse(topUrl)?.hostname;
  if (!frameHost || !topHost) return true;
  return !sameSite(stripWww(frameHost), stripWww(topHost));
}

/** One host being a subdomain of the other is still the same site. */
function sameSite(a, b) {
  return a === b || a.endsWith(`.${b}`) || b.endsWith(`.${a}`);
}

/** `live` when the media has no finite length; `standard` otherwise. */
export function contentFormatFor(duration) {
  return duration === Infinity ? "live" : "standard";
}

/** The media's length, or null when the player has not said. */
export function durationOf(duration) {
  return Number.isFinite(duration) && duration > 0 ? duration : null;
}

/**
 * Everything a View header needs that can be read without an Adapter.
 *
 * `videoIdSource` is the string to hash into the `sha1:` video id — hashing is
 * the caller's job because it is asynchronous in a browser and this stays pure.
 */
export function identify({ frameUrl, topUrl, isTopFrame = true, mediaSrc = "", duration = NaN }) {
  const pageId = idSource(frameUrl);
  const srcId = identifyingSrc(mediaSrc);
  return {
    service: serviceFor(frameUrl),
    contentFormat: contentFormatFor(duration),
    embedded: isEmbedded({ isTopFrame, frameUrl, topUrl }),
    url: normalizeUrl(frameUrl),
    durationSec: durationOf(duration),
    metadataSource: "generic",
    adapterId: null,
    // Two players on one page are two Views, so the media's own source joins the
    // id when it has one.
    videoIdSource: srcId && srcId !== pageId ? `${pageId} ${srcId}` : pageId,
  };
}

/** `navigator.mediaSession.metadata`, flattened to View header fields. */
export function fromMediaSession(metadata) {
  if (!metadata) return {};
  const flattened = {};
  if (metadata.title) flattened.title = metadata.title;
  if (metadata.artist) flattened.author = metadata.artist;
  const artwork = largestArtwork(metadata.artwork);
  if (artwork) flattened.artworkUrl = artwork;
  return flattened;
}

function largestArtwork(artwork) {
  if (!Array.isArray(artwork) || artwork.length === 0) return null;
  const area = (entry) => {
    const [width, height] = String(entry?.sizes ?? "").split("x").map(Number);
    return (width || 0) * (height || 0);
  };
  return [...artwork].sort((a, b) => area(b) - area(a))[0]?.src ?? null;
}

/**
 * What in `next` is news to the View — the payload of a `metadataChange`, or
 * null when there is nothing to report.
 */
export function metadataDiff(view, next) {
  const changed = {};
  for (const [field, value] of Object.entries(next ?? {})) {
    if (value == null || value === "") continue;
    if (view[field] === value) continue;
    changed[field] = value;
  }
  return Object.keys(changed).length > 0 ? changed : null;
}

function parse(url) {
  try {
    return new URL(String(url));
  } catch {
    return null;
  }
}

function stripWww(hostname) {
  return hostname.replace(/^www\./, "");
}
