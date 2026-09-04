// Which source wins each field of a View header.
//
// Four things describe one video and they disagree. The per-Service Adapter
// read the page and knows where the channel name lives. `navigator.mediaSession`
// holds whatever the site wrote for the lock screen. The generic fallback has
// the URL, `og:title` and `document.title`. The `<video>` element knows its own
// length. This module takes all four and produces one header, per the ranking
// pinned by issue #4.
//
// Pure on purpose: no DOM, no extension API, no site knowledge. Everything here
// is decided by looking at four bags of plain values, which is what lets every
// rule below be tested without loading a page.
//
//   field                    ranking
//   ---------------------------------------------------------------------
//   videoId, contentFormat   Adapter -> generic          (never mediaSession)
//   embedded                 router proposes, Adapter may correct
//   title                    mediaSession -> Adapter -> og:title -> document.title
//   author                   Adapter -> mediaSession -> generic
//   durationSec              Adapter -> <video> -> mediaSession
//
// `videoId` never takes mediaSession because there is no id there — only
// strings a human reads, and a title is not an identity: two uploads of one
// song share it. `title` puts mediaSession above the Adapter because it is the
// string the site itself wrote to be read on a lock screen, with no
// "- YouTube" suffix and no channel name bolted on the front. `author` runs the
// other way because mediaSession's artist slot is blank or holds the platform's
// own name on anything that isn't music, while the Adapter read the real
// channel link off the page.

/** The values `metadataSource` may take: where the *title* came from, only. */
export const TITLE_SOURCES = ["mediaSession", "adapter", "generic", "documentTitle"];

/**
 * Did this source actually answer?
 *
 * Absent (`undefined` / `null`) means "no opinion, keep walking the ranking".
 * An empty string means "the answer is genuinely nothing, stop here" — but only
 * from an Adapter, which is the one source that knows a fact rather than
 * guesses one. The Netflix Adapter reports `author: ""` for a film because a
 * film has no show name; without this the ranking would fall through to
 * mediaSession and a fake creator named "Netflix" would accrue hours in the By
 * Service pane. From any other source an empty string is just a field it failed
 * to fill.
 */
function answered(value, { deliberateEmpty = false } = {}) {
  if (value === undefined || value === null) return false;
  return value !== "" || deliberateEmpty;
}

/** Walk a ranking top to bottom; the first source that answered wins. */
function firstAnswer(ranking) {
  for (const [source, value, options] of ranking) {
    if (answered(value, options)) return { source, value };
  }
  return { source: null, value: null };
}

/**
 * One View header from every source that had something to say.
 *
 * @param {object} inputs
 * @param {{ service?: string, embedded?: boolean, adapterId?: string|null }} [inputs.router]
 *   What the router settled at bind time. It — not the Adapter — sets `service`,
 *   and it proposes `embedded`.
 * @param {object|null} [inputs.adapter]  One `read()` snapshot, or null on a
 *   frame the generic fallback is handling alone.
 * @param {{ title?: string, author?: string, durationSec?: number }} [inputs.session]
 *   `navigator.mediaSession.metadata`, flattened.
 * @param {{ durationSec?: number }} [inputs.element]  The `<video>` itself.
 * @param {object} [inputs.generic]  The no-Adapter reading: `service`, `videoId`
 *   (already hashed by the caller), `url`, `contentFormat`, `title` (`og:title`),
 *   `documentTitle`, `author`.
 */
export function merge({ router = {}, adapter = null, session = {}, element = {}, generic = {} } = {}) {
  // An Adapter that could not read the page keeps its id but loses the prose.
  // The rule is fixed and identical for every Adapter: `high` only when the id
  // came from a URL shape it recognises *and* it found a non-empty title.
  const shaky = adapter?.confidence === "low";

  const fromAdapter = (field) => ["adapter", adapter?.[field], { deliberateEmpty: true }];
  const fromSession = (field) => ["mediaSession", session[field]];
  const fromGeneric = (field, source = "generic") => [source, generic[field]];

  // A `low`-confidence Adapter drops below mediaSession for the prose fields.
  // For `title` that changes nothing — mediaSession already outranks the
  // Adapter — so the tie-break only ever moves `author`.
  const title = firstAnswer([
    fromSession("title"),
    fromAdapter("title"),
    fromGeneric("title"),
    fromGeneric("documentTitle", "documentTitle"),
  ]);
  const author = firstAnswer(
    shaky
      ? [fromSession("author"), fromAdapter("author"), fromGeneric("author")]
      : [fromAdapter("author"), fromSession("author"), fromGeneric("author")],
  );

  return {
    service: router.service ?? generic.service ?? "unknown",
    // A shaky id still beats no id, so the Adapter stays top here whatever its
    // confidence says.
    videoId: firstAnswer([fromAdapter("videoId"), fromGeneric("videoId")]).value,
    contentFormat: firstAnswer([fromAdapter("contentFormat"), fromGeneric("contentFormat")]).value ?? "standard",
    embedded: answered(adapter?.embedded) ? !!adapter.embedded : !!router.embedded,
    url: generic.url ?? null,
    title: title.value,
    author: author.value,
    durationSec: firstAnswer([
      fromAdapter("durationSec"),
      ["element", element.durationSec],
      fromSession("durationSec"),
    ]).value,
    // Provenance, minimally: which Adapter ran, and where the title — and only
    // the title — came from. Per-field provenance was rejected as storage
    // nobody queries.
    metadataSource: title.source,
    adapterId: router.adapterId ?? null,
  };
}
