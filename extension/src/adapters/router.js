// Which Adapter this frame gets.
//
// Closed and built in: adding an Adapter means editing the list below and
// rebuilding the extension. No runtime registration, no third-party Adapters.
//
// The lookup is a map from host suffix to Adapter, built once when this module
// loads, then walked most-specific-first over the frame's hostname —
// `a.b.example.com`, `b.example.com`, `example.com` — taking the first hit. The
// cost is the number of labels in a hostname, never the number of Adapters.
//
// This function is stateless — it re-derives the answer from `location` and
// `document` on every call, and normally that happens once, at first sight of
// a player: clicking through to the next Short or the next episode doesn't
// call it again, since the same Adapter still claims the page and simply
// reports a new `videoId`. The exception is a site with a client-side router
// of its own (YouTube): a page that starts on a video-less URL (the home
// feed, a search) is correctly declined here, but the site can then swap in a
// real video without ever reloading the page, so the caller (`content.js`)
// listens for that site's own navigation signal and calls this again when it
// fires. A forty-Short binge, or an hour on the home feed with one video
// finally clicked, both still cost one lookup each.

import { serviceFor } from "../identify.js";
import { NetflixAdapter } from "./netflix.js";
import { YouTubeAdapter } from "./youtube.js";

/** The shipped set, in order. `GenericAdapter` is not in here: it is what you
 *  get when nothing in here wants the page, and it lives in `generic.js`. */
export const ADAPTERS = [YouTubeAdapter, NetflixAdapter];

/** @returns {Map<string, object>} host suffix -> the Adapter claiming it */
export function buildHostMap(adapters) {
  const map = new Map();
  for (const adapter of adapters) {
    // Ordered: the first Adapter to claim a suffix keeps it.
    for (const pattern of adapter.hostPatterns) if (!map.has(pattern)) map.set(pattern, adapter);
  }
  return map;
}

const HOST_MAP = buildHostMap(ADAPTERS);

/** Walk `a.b.example.com` -> `b.example.com` -> `example.com`, first hit wins. */
function walkHost(hostname, hostMap) {
  const labels = String(hostname ?? "").split(".");
  for (let i = 0; i < labels.length - 1; i += 1) {
    const hit = hostMap.get(labels.slice(i).join("."));
    if (hit) return hit;
  }
  return null;
}

/**
 * The Adapter for this frame, or none — decided once, at document load.
 *
 * `matches()` is the Adapter's own veto, checked here and only here: the host
 * matched, but the Adapter has looked at the URL and does not recognise a video
 * on it (a channel page, a browse page, YouTube Music). A veto falls through to
 * the generic fallback exactly as a missing Adapter does.
 *
 * @returns {{ adapter: object|null, adapterId: string|null, service: string }}
 */
export function bindAdapter({ location, document }, hostMap = HOST_MAP) {
  const url = new URL(location.href);
  const claimed = walkHost(url.hostname, hostMap);

  if (!claimed || (claimed.matches && !claimed.matches(url))) {
    return { adapter: null, adapterId: null, service: serviceFor(url.href) };
  }
  return {
    adapter: claimed.create({ location, document }),
    adapterId: claimed.id,
    // The router names the Service, never the Adapter — one less thing an
    // Adapter can get wrong, and the only place the fallback and the shipped
    // names have to agree.
    service: claimed.service,
  };
}

// Exposed for the test that pins the walk order; not part of the interface.
bindAdapter.walkHost = walkHost;
