// The Netflix Adapter.
//
// Simpler than YouTube in every direction: one URL shape, one content format,
// and a player that draws its title into one small block. The only judgement
// in here is series versus film, and it is made by whether an episode name
// exists — a film's block holds nothing but the film's name.
//
// `contentFormat` is always `standard`. Netflix has no Shorts, and its live
// events are out of scope for v1.

import { confidenceOf, firstText, observeTitle } from "./shared.js";

/** `/watch/NNNNNNNN`, with or without a country prefix like `/gb/`. */
const WATCH_PATH = /(?:^|\/)watch\/(\d+)/;

/** The show, or a film's own name. `data-uia` first: it is Netflix's test hook. */
const SHOW_SELECTORS = ["[data-uia=video-title] h4", ".video-title h4"];

/**
 * The episode name. The block holds `E4` and the name as two spans, so the
 * last one is the name; a film has no such span at all.
 */
const EPISODE_SELECTORS = [
  "[data-uia=video-title] span:last-of-type",
  ".video-title span:last-of-type",
];

function videoIdFrom(url) {
  return url.pathname.match(WATCH_PATH)?.[1];
}

export const NetflixAdapter = {
  id: "netflix",
  service: "netflix",
  hostPatterns: ["netflix.com"],

  matches(url) {
    return videoIdFrom(url) !== undefined;
  },

  create({ location, document }) {
    return {
      read() {
        const videoId = videoIdFrom(new URL(location.href));
        const show = firstText(document, SHOW_SELECTORS);
        const episode = firstText(document, EPISODE_SELECTORS);

        // Series: the show is the author and the episode rides in the title,
        // because the wire carries no season or episode fields. Film: the
        // author is *known* to be nothing, which is not the same as unknown —
        // the empty string stops the ranking before mediaSession can offer
        // "Netflix" as the creator of Glass Onion.
        const title = show && episode ? `${show} - ${episode}` : show;
        const author = show ? (episode ? show : "") : undefined;

        return {
          videoId,
          contentFormat: "standard",
          ...(title === undefined ? {} : { title }),
          ...(author === undefined ? {} : { author }),
          confidence: confidenceOf(videoId, title),
        };
      },
      onChange(cb) {
        return observeTitle(document, cb);
      },
    };
  },
};
