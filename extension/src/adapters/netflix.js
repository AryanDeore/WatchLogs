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

const METADATA_TTL_MS = 60_000;

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

function metadataUrl(watchId) {
  const url = new URL("https://www.netflix.com/nq/website/memberapi/release/metadata");
  url.searchParams.set("movieid", watchId);
  url.searchParams.set("_", String(Date.now()));
  return url;
}

function pickEpisode(video, watchId) {
  const wanted = String(watchId ?? video?.currentEpisode ?? "");
  for (const season of video?.seasons ?? []) {
    for (const episode of season?.episodes ?? []) {
      if (String(episode?.episodeId ?? "") === wanted) return episode;
    }
  }
  return null;
}

function asPositiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : undefined;
}

function fromMetadata(video, watchId) {
  if (!video || typeof video !== "object") return null;
  const showOrMovie = typeof video.title === "string" && video.title.trim() ? video.title.trim() : undefined;
  if (!showOrMovie) return null;

  if (video.type === "show") {
    const episode = pickEpisode(video, watchId);
    const episodeTitle = typeof episode?.title === "string" && episode.title.trim() ? episode.title.trim() : undefined;
    return {
      ...(episodeTitle ? { title: `${showOrMovie} - ${episodeTitle}` } : { title: showOrMovie }),
      author: showOrMovie,
      ...(asPositiveNumber(episode?.runtime) === undefined ? {} : { durationSec: asPositiveNumber(episode?.runtime) }),
    };
  }

  return {
    title: showOrMovie,
    author: "",
    ...(asPositiveNumber(video.runtime) === undefined ? {} : { durationSec: asPositiveNumber(video.runtime) }),
  };
}

export const NetflixAdapter = {
  id: "netflix",
  service: "netflix",
  hostPatterns: ["netflix.com"],

  matches(url) {
    return videoIdFrom(url) !== undefined;
  },

  create({ location, document }) {
    const cache = new Map();
    const inFlight = new Set();
    const listeners = new Set();

    function notify() {
      for (const cb of listeners) cb();
    }

    function primeMetadata(watchId) {
      if (!watchId) return;
      const cached = cache.get(watchId);
      if (cached && Date.now() - cached.at < METADATA_TTL_MS) return;
      if (inFlight.has(watchId)) return;

      inFlight.add(watchId);
      fetch(metadataUrl(watchId))
        .then((response) => (response.ok ? response.json() : null))
        .then((payload) => {
          const mapped = fromMetadata(payload?.video, watchId);
          if (!mapped) return;
          cache.set(watchId, { at: Date.now(), mapped });
          notify();
        })
        .catch(() => {})
        .finally(() => {
          inFlight.delete(watchId);
        });
    }

    return {
      read() {
        const videoId = videoIdFrom(new URL(location.href));
        primeMetadata(videoId);

        const fromApi = videoId ? cache.get(videoId)?.mapped : null;
        const show = firstText(document, SHOW_SELECTORS);
        const episode = firstText(document, EPISODE_SELECTORS);

        const title = fromApi?.title ?? (show && episode ? `${show} - ${episode}` : show);
        const author = fromApi?.author ?? (show ? (episode ? show : "") : undefined);

        return {
          videoId,
          contentFormat: "standard",
          ...(title === undefined ? {} : { title }),
          ...(author === undefined ? {} : { author }),
          ...(fromApi?.durationSec === undefined ? {} : { durationSec: fromApi.durationSec }),
          confidence: confidenceOf(videoId, title),
        };
      },
      onChange(cb) {
        listeners.add(cb);
        const unobserve = observeTitle(document, cb);
        return () => {
          listeners.delete(cb);
          unobserve();
        };
      },
    };
  },
};
