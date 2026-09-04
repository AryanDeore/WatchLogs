// The YouTube Adapter: watch pages, Shorts, live, and embeds on both of
// YouTube's hosts.
//
// The id always comes off the URL, never the page. That is the whole reason
// this Adapter survives a YouTube redesign: the markup around the title moves
// every few months, but `watch?v=`, `/shorts/`, `/live/` and `/embed/` have
// been stable for years. When the redesign does take the title away, `read()`
// reports `low` confidence and mediaSession supplies the prose while the id
// carries on being right.
//
// Not handled: `music.youtube.com`, and any page without a video of its own —
// a channel, a playlist, the home feed. Both step aside at bind time via
// `matches()` and fall through to the generic fallback.

import { confidenceOf, firstText, observeTitle } from "./shared.js";

/** Where the title sits, best first. A Short's heading is not the watch one. */
const TITLE_SELECTORS = [
  ".ytShortsVideoTitleViewModelShortsVideoTitle", // Shorts
  "#above-the-fold h1", // watch / live
  "h1.ytd-watch-metadata", // watch, older layout
  ".ytp-title-link", // the player's own bar, which is all an embed has
];

/** The channel name. The same element serves watch, live and Shorts. */
const AUTHOR_SELECTORS = [
  "yt-formatted-string#text.ytd-channel-name",
  ".ytReelChannelBarViewModelChannelName",
  "link[itemprop=name]",
  ".ytp-title-channel-name",
];

/**
 * The schema.org marker YouTube emits only on an actual broadcast.
 *
 * Not `.ytp-live-badge`: that element is in every watch page's player markup,
 * hidden, so its presence says nothing and a visibility check would need CSS
 * that a saved fixture does not have.
 */
const LIVE_MARKER = "[itemprop=isLiveBroadcast]";

/** `/shorts/ID`, `/live/ID`, `/embed/ID` — the shapes that carry the id in the path. */
const PATH_SHAPES = [
  { prefix: "/shorts/", contentFormat: "short" },
  { prefix: "/live/", contentFormat: "live" },
  { prefix: "/embed/", contentFormat: null, embedded: true },
];

/**
 * What this URL says about the video, or null if it names no video at all.
 *
 * `contentFormat: null` means "the page has to say" — a watch page or an embed
 * is standard unless the live marker is there.
 */
function fromUrl(url) {
  // YouTube Music is a different product on the same domain, with its own
  // player and its own URL shapes. Out of scope for v1: it falls through.
  if (url.hostname.split(".")[0] === "music") return null;

  if (url.pathname === "/watch") {
    // A URL can carry both a video and the playlist it was opened from. The
    // video is what is playing.
    const videoId = url.searchParams.get("v");
    return videoId ? { videoId, contentFormat: null } : null;
  }

  for (const shape of PATH_SHAPES) {
    if (!url.pathname.startsWith(shape.prefix)) continue;
    const videoId = url.pathname.slice(shape.prefix.length).split("/")[0];
    return videoId ? { ...shape, videoId } : null;
  }
  return null;
}

export const YouTubeAdapter = {
  id: "youtube",
  service: "youtube",
  hostPatterns: ["youtube.com", "youtube-nocookie.com"],

  /** Checked once, at bind time: is there a video on this page for us to read? */
  matches(url) {
    return fromUrl(url) !== null;
  },

  create({ location, document }) {
    return {
      read() {
        const url = new URL(location.href);
        const shape = fromUrl(url) ?? {};
        const title = firstText(document, TITLE_SELECTORS);
        return {
          videoId: shape.videoId,
          contentFormat: shape.contentFormat ?? (document.querySelector(LIVE_MARKER) ? "live" : "standard"),
          ...(shape.embedded ? { embedded: true } : {}),
          ...(title === undefined ? {} : { title }),
          ...withAuthor(document),
          confidence: confidenceOf(shape.videoId, title),
        };
      },
      onChange(cb) {
        return observeTitle(document, cb);
      },
    };
  },
};

/** Absent, not empty: a channel name we could not find is not a channel of "". */
function withAuthor(document) {
  const author = firstText(document, AUTHOR_SELECTORS);
  return author === undefined ? {} : { author };
}
