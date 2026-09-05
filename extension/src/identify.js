// Generic, best-effort identification. Pure: it is handed strings and numbers
// the page helper read off the page, never the page itself.
//
// This is the no-Adapter fallback — what can be known about a video from the
// URL and the media element alone, on a site nobody has written a reader for.
// A per-Service Adapter overrides it field by field in `metadata.js`; where no
// Adapter is bound, everything below is the whole answer.

/** Query params that move without the video moving. */
const NON_IDENTIFYING_PARAMS = new Set([
  "t", "start", "time_continue", "autoplay", "mute", "loop", "controls",
  "list", "index", "playlist", "pp", "si", "feature", "app", "ref", "ref_src",
  "fbclid", "gclid", "igshid", "spm", "share", "shared", "source",
]);

/**
 * Endings that are *not* a site on their own: `bbc.co.uk` is somebody's site,
 * `co.uk` is not. The real answer is the Public Suffix List, ~10k entries the
 * browsers keep internally and expose to nobody, so this is the common ~30 —
 * enough that the By Service pane doesn't split a platform in two over a
 * subdomain, small enough to read.
 *
 * Deliberately approximate. `aryan.github.io` and `someone-else.github.io`
 * both come out as `github.io`; the accepted trade for not shipping the list.
 */
const MULTI_PART_ENDINGS = new Set([
  "co.uk", "org.uk", "me.uk", "ac.uk", "gov.uk", "net.uk", "sch.uk",
  "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au",
  "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp",
  "co.nz", "net.nz", "org.nz", "govt.nz",
  "co.za", "org.za", "web.za",
  "com.br", "com.mx", "com.ar", "com.tr", "com.cn", "com.hk", "com.sg",
  "com.tw", "com.pl", "com.ua", "co.in", "co.kr", "co.il",
]);

/** An IPv4 address, or the `[...]` form the URL parser gives an IPv6 host. */
const IP_ADDRESS = /^(\[.*\]|\d+(\.\d+){3})$/;

/**
 * The site a hostname belongs to: `music.youtube.com` and `www.youtube.com` are
 * both `youtube.com`, so one platform is one row in the By Service pane rather
 * than one row per subdomain.
 *
 * Anything without at least two labels — `localhost`, an IP address — is
 * already as short as it goes and comes back untouched.
 */
export function registrableDomain(hostname) {
  const host = String(hostname ?? "");
  // An address is not a name: `127.0.0.1` has no site to shorten it to, and
  // trimming labels off one would report a different machine.
  if (IP_ADDRESS.test(host)) return host;
  const labels = host.split(".").filter(Boolean);
  if (labels.length < 3) return labels.join(".");
  const lastTwo = labels.slice(-2).join(".");
  const keep = MULTI_PART_ENDINGS.has(lastTwo) ? 3 : 2;
  return labels.slice(-keep).join(".");
}

/**
 * The Service of a site with no Adapter: its registrable domain. `service`
 * rides the wire as a required, non-empty field, so a URL that parses but has
 * no host — `about:blank` (every `match_about_blank` iframe), `about:srcdoc`,
 * `file:` — falls back to "unknown" exactly like one that fails to parse.
 */
export function serviceFor(url) {
  const parsed = parse(url);
  const host = parsed ? registrableDomain(parsed.hostname) : "";
  return host || "unknown";
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

/**
 * The string a generic video id is hashed from: origin and path, nothing else.
 *
 * Dropping the query is deliberate and has a known cost. A site that keeps its
 * id in `?v=` collapses every one of its videos into a single id — and a site
 * like that is exactly the one that then shows up in the app's "needs an
 * Adapter" flag, which is how you find out it needs one. `www.` comes off so a
 * link that has it and a link that doesn't are the same video.
 */
export function videoIdSourceFor(url) {
  const parsed = parse(url);
  if (!parsed) return String(url ?? "");
  const path = parsed.pathname.replace(/\/+$/, "") || "/";
  return `${parsed.protocol}//${stripWww(parsed.hostname)}${path}`;
}

/** A media source only tells two players apart when it is a real, stable URL. */
export function identifyingSrc(mediaSrc) {
  const parsed = parse(mediaSrc);
  return parsed && (parsed.protocol === "http:" || parsed.protocol === "https:")
    ? videoIdSourceFor(mediaSrc)
    : null;
}

/**
 * Has this element been handed different media than its View was opened for?
 *
 * YouTube's Shorts feed reuses one player: scrolling to the next Short points
 * the element at new media a beat *before* the router puts the new id in the
 * address bar. In that gap `navigator.mediaSession` already describes the next
 * Short while `videoIdSourceFor` still reads the last one, so a metadata report
 * lands the next Short's title on the View that is still open for the previous
 * one — which is how a 50-second watch ends up filed under a video the user
 * never saw.
 *
 * `currentSrc` is the tell the address bar cannot give: a different resource is
 * a different video, whatever the URL still says. Compared raw rather than
 * through `identifyingSrc`, because the `blob:` URL an MSE player attaches is
 * useless for telling two *players* apart but exact for telling two *videos*
 * apart in one element. A player that had no source when its View opened has
 * nothing to compare against, and is not a swap.
 */
export function isMediaSwap({ openedWith, current }) {
  if (!openedWith || !current) return false;
  return openedWith !== current;
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
 * `navigator.mediaSession.metadata`, flattened to View header fields.
 *
 * Artwork is read and then thrown away — deliberately. The thumbnail is not
 * captured, not stored and not on the wire (#4): no v1 pane shows it, and the
 * only thing it would add is load time.
 */
export function fromMediaSession(metadata) {
  if (!metadata) return {};
  const flattened = {};
  if (metadata.title) flattened.title = metadata.title;
  if (metadata.artist) flattened.author = metadata.artist;
  return flattened;
}

/**
 * What in `next` is news to the View — the payload of a `metadataChange`, or
 * null when there is nothing to report.
 */
export function metadataDiff(view, next) {
  const changed = {};
  for (const [field, value] of Object.entries(next ?? {})) {
    // `null` is a source with nothing to say. An empty string is not: an
    // Adapter reporting `author: ""` for a film means the film has no show
    // name, and that is news worth recording.
    if (value == null) continue;
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
