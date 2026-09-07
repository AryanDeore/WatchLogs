// The page helper. Runs in every frame of every page, watches the media
// elements it finds there, and turns what they do into raw Events.
//
// It owns the capture cadence end to end: the 5-second `sample` timer, the
// per-View `seq`, and the on-disk buffer. The background worker owns only the
// POST, the Ack and the prune — so an evicted worker costs a little latency,
// never a lost Event.
//
// It binds one Adapter per frame at first sight of a player and keeps it until
// the page's own client-side router says the ground moved: clicking through to
// the next Short or the next episode doesn't re-route, since the same Adapter
// still claims the page and simply reports a new video id — but landing on a
// video from a page the Adapter had declined (the home feed, a search, a
// channel) does, because nothing else would ever tell this frame the page
// changed out from under it.
//
// Nothing here interprets anything. `hidden` is recorded as `hidden`, a muted
// PiP player is recorded exactly like any other; Segments, Background audio and
// Watched time are the App's job.
//
// This script lands in every frame of every page, including the dozens of tiny
// ad frames that will never hold a player, so it starts as nothing but a
// handful of listeners. The modules, the handshake with the worker and the
// Capture are all built on the first media event the frame actually sees.

(() => {
  const SAMPLE_MS = 5000;
  const DISCOVERY_MS = 1000;
  const DEBUG_TRACE = true;

  /**
   * How long to wait for metadata to settle before reporting it.
   *
   * A page that has just swapped videos spends about a second with the new id
   * and the old title, filling one field at a time. Every source has this
   * flicker — the Adapter's DOM and `mediaSession` alike — so every source is
   * reported through the same wait, and one `metadataChange` covers everything
   * that moved.
   */
  const META_DEBOUNCE_MS = 500;
  const SHORTS_MEDIASESSION_SETTLE_MS = 1500;

  /**
   * How long a paused View may sit untouched before it is no longer active.
   *
   * One minute is deliberate: long enough not to split a normal "pause to read
   * comments" into extra Views, short enough that an abandoned tab does not
   * stay open for hours.
   */
  const PAUSED_OUT_MS = 60_000;

  /**
   * Media event -> what it means, in one table so the two can't drift apart.
   * `action` is null where the event only means "re-read the element".
   * `flush` marks the ones worth waking the worker for straight away, rather
   * than waiting for the next 5-second beat.
   * `needsAdvance` marks the ones that only mean what they say if the player
   * is actually moving — see `vouched`.
   */
  const MEDIA_EVENTS = {
    loadedmetadata: {},
    durationchange: {},
    play: { action: () => ({ type: "PLAY" }), needsAdvance: true },
    playing: { action: () => ({ type: "PLAY" }), needsAdvance: true },
    pause: { action: () => ({ type: "PAUSE" }), flush: true },
    ended: { action: () => ({ type: "MEDIA_ENDED" }), flush: true },
    ratechange: { action: (fact) => ({ type: "RATE", rate: fact.rate }) },
    seeked: { action: (fact, entry) => ({ type: "SEEKED", from: entry.pos, to: fact.pos }) },
    enterpictureinpicture: { action: () => ({ type: "PIP_ENTER" }) },
    leavepictureinpicture: { action: () => ({ type: "PIP_LEAVE" }) },
  };

  /**
   * Is this element large enough, and actually rendered, to plausibly be a
   * video someone is looking at — as opposed to the couple of pixels an ad
   * network's viewability-tracking `<video>` renders at, or a decoy someone
   * has hidden outright? A handful of CSS pixels or a `display: none` is
   * never a real player; it is the shape those trackers leave behind.
   */
  function isVisiblyPlayable(media) {
    const rect = media.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return false;
    const style = getComputedStyle(media);
    return style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
  }

  /** The running capture context, once a player has shown up. */
  let helper = null;
  let booting = null;
  let captureDisabled = false;
  const queued = [];

  // Media events don't bubble, so each one is a capture-phase listener on the
  // root: one registration catches players that don't exist yet.
  for (const type of Object.keys(MEDIA_EVENTS)) {
    document.addEventListener(
      type,
      (event) => {
        if (!(event.target instanceof HTMLMediaElement) || captureDisabled) return;
        // Snapshot the facts at the moment they were true: booting is
        // asynchronous, and `currentTime` will have moved on by the time it
        // finishes.
        const fact = {
          kind: type,
          media: event.target,
          at: Date.now(),
          pos: event.target.currentTime,
          rate: event.target.playbackRate,
          visible: document.visibilityState === "visible",
          // `isAdvancing`'s three inputs, snapshotted with the rest: whether a
          // `play` was real is a fact about the instant it fired, and the
          // element will have moved on by the time a queued fact is handled.
          paused: event.target.paused,
          ended: event.target.ended,
          readyState: event.target.readyState,
        };
        if (helper) helper.handle(fact);
        else {
          // Bounded: if the worker never answers, this frame stops remembering
          // rather than growing a queue for the life of the page.
          if (queued.length < 200) queued.push(fact);
          void boot();
        }
      },
      true,
    );
  }

  // Keeps `from` on the next seek honest, for players we already know about.
  document.addEventListener(
    "timeupdate",
    (event) => helper?.note(event.target, event.target.currentTime),
    true,
  );

  document.addEventListener("visibilitychange", () =>
    helper?.setVisible(document.visibilityState === "visible"),
  );

  addEventListener("pagehide", () => helper?.endAll("nav"));

  // A tab Chromium froze and later thawed is the one suspension the page is
  // actually told about. Everything else — a closed lid, a suspended process —
  // is only ever inferred from the clock, which is why `noticeWake` runs on the
  // ordinary beat too rather than only here.
  document.addEventListener("resume", () => helper?.noticeWake(Date.now()));

  function boot() {
    if (captureDisabled) return Promise.resolve(null);
    // A failed boot resets, so the next media event tries again — the worker may
    // simply have been mid-restart.
    return (booting ??= start().catch(() => {
      booting = null;
      return null;
    }));
  }

  async function start() {
    // `hello` doubles as a barrier: the worker answers only once it has closed
    // whatever a previous browser run left open, so no View we write now can be
    // mistaken for a crashed one. It also tells this frame whether its tab is a
    // private window, before any capture modules or state are initialized.
    const hello = await ask({ type: "hello" });
    if (!hello) throw new Error("the WatchLogs worker did not answer");
    if (hello.incognito && !hello.capturePrivateWindows) {
      captureDisabled = true;
      queued.length = 0;
      return null;
    }

    const load = (path) => import(chrome.runtime.getURL(path));
    const [captureModule, bufferModule, metaModule, idsModule, mergeModule, routerModule, genericModule, sharedModule] =
      await Promise.all([
        load("src/capture.js"),
        load("src/buffer.js"),
        load("src/identify.js"),
        load("src/ids.js"),
        load("src/metadata.js"),
        load("src/adapters/router.js"),
        load("src/adapters/generic.js"),
        load("src/adapters/shared.js"),
      ]);

    helper = makeHelper({
      capture: captureModule,
      buffer: bufferModule,
      meta: metaModule,
      ids: idsModule,
      merge: mergeModule.merge,
      bindAdapter: routerModule.bindAdapter,
      readGeneric: genericModule.readGeneric,
      observeTitle: sharedModule.observeTitle,
      hello,
    });
    for (const fact of queued.splice(0)) helper.handle(fact);
    return helper;
  }

  function ask(message) {
    return chrome.runtime.sendMessage(message).catch(() => null);
  }

  function debugTrace(event, data = {}) {
    if (!DEBUG_TRACE) return;
    const entry = {
      event,
      href: location.href,
      ...data,
    };
    // Fast local signal while reproducing in DevTools.
    console.debug("[WatchLogs trace]", entry);
    // Persisted ring-buffer trace in extension storage.
    void ask({ type: "debugTrace", entry });
  }

  // --- The capture context ------------------------------------------------------

  function makeHelper({
    capture: captureModule,
    buffer,
    meta,
    ids,
    merge,
    bindAdapter,
    readGeneric,
    observeTitle,
    hello,
  }) {
    const { apply, initCapture, isAdvancing, unwatchedGapMs, SUSPENDED_MS } = captureModule;
    const runId = hello.runId;
    const capture = initCapture(Date.now(), { tabId: hello.tabId ?? 0 });
    // A tab opened in the background starts hidden; without this the first
    // `visible` would look like a transition that never happened.
    capture.tabVisible = document.visibilityState === "visible";

    // One Adapter for this frame, chosen at first sight of a player and kept
    // until `rebind` says otherwise. Routing happens here, at the first sight
    // of a player, rather than at document load: most frames on most pages
    // never hold one, and an ad iframe should not pay for a lookup it will
    // never use.
    let bound = bindAdapter({ location, document });
    let lastBoundHref = location.href;

    /** media element -> { viewId, key, pos, disambiguate } */
    const tracked = new Map();
    let forcingNetflixRebind = false;
    /** viewId -> the highest seq already on disk */
    const persisted = new Map();
    const idCache = new Map();
    /**
     * videoId -> viewId for views currently being opened (during ensureView).
     * Prevents race conditions where multiple <video> elements for the same
     * video all fire events before any has been added to tracked.
     */
    const pendingOpens = new Map();
    /**
     * media element -> a stable disambiguation key, minted once per element
     * and kept for its life in this frame. An ad slot that swaps its
     * `currentSrc` on every loop is still the same element; keying on the
     * element itself (rather than the source it happens to be showing right
     * now) keeps that one slot one id across every loop, instead of minting a
     * fresh View each time the source churns.
     */
    const slotKeys = new WeakMap();
    let nextSlot = 0;
    let sampleTimer = null;
    let discoveryTimer = null;
    /** viewId -> paused-out timeout id */
    const pausedOutTimers = new Map();
    /**
     * The last instant this frame can vouch for: the beat that ran, or the
     * moment the timer started. `null` whenever no timer is running, because
     * with nothing advancing there is no clock to lose.
     */
    let lastHeartbeatAt = null;
    let metaTimer = null;
    let writing = Promise.resolve();

    // The Adapter's own signal that the page moved under it — and, on a frame
    // with no Adapter, the same watcher over the page title. Neither reports
    // anything directly: both only start the wait.
    let unwatchMetadata = watchMetadata();
    ensureDiscoveryTimer();

    // YouTube's own router announces a client-side navigation with this event,
    // fired on `document` — the one page-change shape `bindAdapter` never
    // otherwise sees. A frame whose first URL had no video (the home feed, a
    // search, a channel) is declined at first sight and, without this, stays
    // declined forever: clicking into an actual video only ever swaps the URL
    // and the player's contents, it never reloads the page that made the
    // original, now-stale decision. Harmless to register on every frame — the
    // event simply never fires anywhere but youtube.com.
    document.addEventListener("yt-navigate-finish", rebind);

    function watchMetadata() {
      return bound.adapter ? bound.adapter.onChange(scheduleMetadata) : observeTitle(document, scheduleMetadata);
    }

    /**
     * Re-run the same routing decision `bound` was made from, now that the
     * page underneath it has changed, and immediately re-read every player
     * still open against it — rather than leaving that to whatever media
     * event or the 5-second tick happens to fire next. YouTube reuses one
     * `<video>` element across a client-side navigation, so the element that
     * was tracked under the stale Adapter is still the right one to re-read;
     * `refresh` sees the newly bound Adapter's real video id differ from the
     * stale generic one and closes that View for a correctly identified one,
     * the same path an ordinary video-to-video change already takes. This is
     * what keeps the gap between "the page navigated" and "this frame knows
     * it" down to one event-loop turn instead of up to one tick interval.
     */
    function rebind() {
      unwatchMetadata();
      bound = bindAdapter({ location, document });
      lastBoundHref = location.href;
      unwatchMetadata = watchMetadata();

      // Netflix and similar Adapter-covered hosts can client-route from a real
      // watch page to a browse/preview URL without reloading. Once the Adapter
      // declines the new URL, any View still open belongs to the page before
      // that navigation and must close now rather than keep sampling previews.
      if (!bound.adapter && bound.adapterCovered) {
        endAll("nav");
        return;
      }

      const at = Date.now();
      for (const [media, entry] of [...tracked]) {
        if (isOpen(entry.viewId)) refresh(media, { at, pos: media.currentTime });
      }
    }

    function refreshBindingIfUrlChanged() {
      if (location.href === lastBoundHref) return;
      rebind();
    }

    return { handle, note, setVisible, endAll, noticeWake };

    // --- What just happened -----------------------------------------------------

    function handle(fact) {
      refreshBindingIfUrlChanged();
      noticeWake(fact.at);
      const entry = ensureView(fact.media, fact);
      if (!entry) return;

      const meaning = MEDIA_EVENTS[fact.kind];
      if (meaning.action && vouched(fact, meaning)) act(fact, meaning.action(fact, entry), meaning.flush);
      else refresh(fact.media, fact);
      persistAll();
      ensureTimer();
    }

    /**
     * Does this event mean what it says?
     *
     * `play` fires when playback is *requested*, not when it happens. A player
     * the browser has suspended — a tab opened in the background it never
     * decoded a frame for — sits at `paused === false` with a `readyState`
     * saying it has nothing to play, and its `currentTime` never moves.
     * Recording that as playback banks Watched time for a video nobody watched
     * (#40), and nothing arrives later to take it back: no `pause` is coming,
     * because nothing ever started.
     *
     * So the Event is dropped and the beat is left to open the Segment when
     * the player actually moves — at an instant it can vouch for, which is the
     * same conservative boundary the App draws for any change it only learns
     * about from a heartbeat.
     */
    function vouched(fact, meaning) {
      return !meaning.needsAdvance || isAdvancing(fact);
    }

    function note(media, pos) {
      const entry = tracked.get(media);
      if (entry) entry.pos = pos;
    }

    function setVisible(visible) {
      noticeWake(Date.now());
      const viewId = anyOpenViewId();
      apply(capture, {
        type: visible ? "SHOW" : "HIDE",
        at: Date.now(),
        viewId,
        pos: positionOf(viewId),
      });
      // A tab Chromium froze while hidden can hold a `<video>` whose duration
      // never resolved — the browser drops events a frozen document was not
      // running to receive, and nothing else ever asks again. Coming into view
      // is the one moment that duration is trustworthy again, so it is exactly
      // the moment to re-describe every open player rather than trust whatever
      // `metadataDiff` last had to say.
      if (visible) scheduleMetadata();
      persistAll(true);
    }

    /** The last position we saw for a View, if we are still tracking its player. */
    function positionOf(viewId) {
      for (const entry of tracked.values()) if (entry.viewId === viewId) return entry.pos;
      return undefined;
    }

    /**
     * A View that outlives its page is a View nobody will ever close, so say so
     * on the way out. Best-effort: if the frame dies before the write lands, the
     * View is recovered from its last `sample` on the next browser run.
     */
    function endAll(reason) {
      // Before anything is stamped at "now": if the frame has been asleep, now
      // is hours past the last thing it actually saw, and ending the View here
      // would bank every one of them.
      noticeWake(Date.now());
      // A wait still running has its say now: what it is holding is the last
      // thing anyone will ever learn about this View.
      if (metaTimer !== null) reportMetadata();
      for (const [media, entry] of tracked) {
        if (!isOpen(entry.viewId)) continue;
        // Clean up pending opens when view ends
        pendingOpens.delete(entry.key);
        apply(capture, {
          type: "VIEW_ENDED",
          at: Date.now(),
          viewId: entry.viewId,
          pos: media.currentTime,
          reason,
        });
        cancelPausedOut(entry.viewId);
      }
      persistAll(true);
      // Nothing is tracked any more, so this stops the beat and drops the
      // heartbeat anchor with it. Without that, a page coming back out of the
      // back/forward cache — routine on Gecko — meets a timer still holding an
      // anchor from before it was cached, and reads the cached stretch as a
      // suspension with no players left to account for it.
      ensureTimer();
    }

    // --- The 5-second heartbeat --------------------------------------------------

    /**
     * A player that *wants* to play, whether or not it is getting anywhere.
     *
     * The beat used to run only while something was advancing, which left the
     * one case that most needed watching unobserved: a suspended player sits
     * at `paused === false` and never advances, so no beat ran, so nothing
     * ever contradicted whatever the log last said about it (#40). Beating
     * through it costs one sample every 5s — one a minute once the tab is
     * throttled — and each one reports `playing: false`, which is the evidence
     * the App needs to close a Segment that should never have stayed open.
     */
    function wantsToPlay(media) {
      return !media.paused && !media.ended;
    }

    function ensureTimer() {
      const playing = [...tracked.keys()].some(wantsToPlay);
      if (playing && sampleTimer === null) {
        sampleTimer = setInterval(tick, SAMPLE_MS);
        lastHeartbeatAt = Date.now();
      } else if (!playing && sampleTimer !== null) {
        clearInterval(sampleTimer);
        sampleTimer = null;
        lastHeartbeatAt = null;
      }
    }

    function ensureDiscoveryTimer() {
      if (discoveryTimer !== null) return;
      discoveryTimer = setInterval(discoverNow, DISCOVERY_MS);
    }

    function discoverNow() {
      refreshBindingIfUrlChanged();
      const at = Date.now();
      const visible = document.visibilityState === "visible";
      const bootstrapped = bootstrapUntrackedPlayers(at, visible);
      if (bootstrapped) {
        persistAll();
        ensureTimer();
      }
    }

    /**
     * Close the books on wall clock this frame was not running for.
     *
     * The one thing the Extension cannot observe is its own absence — a closed
     * lid, a frozen tab, a renderer that never got to fire `pause`. Nothing
     * marks the start of it and the beat that resumes afterwards looks exactly
     * like the beat before, so left alone a four-hour nap arrives at the App as
     * four hours of watching.
     *
     * `unwatchedGapMs` is what separates that from a tab merely beating slowly.
     * Where it says a real stretch went unwatched, every open View is paused at
     * the last beat that actually ran — never at wake time, which would bank the
     * whole gap — and whatever is genuinely still moving is played again now. The
     * uncertain middle counts for nobody, the same conservative boundary the App
     * draws for a heartbeat that reveals a change it never saw.
     *
     * Safe to call from anywhere and as often as anything likes: with no timer
     * running, or a gap the players can account for, it does nothing.
     */
    function noticeWake(at) {
      if (lastHeartbeatAt === null || !(at > lastHeartbeatAt)) return;

      const players = [];
      for (const [media, entry] of tracked) {
        const beforeSleep = capture.lastSampleSnapshot[entry.viewId];
        if (!isOpen(entry.viewId) || !beforeSleep) continue;
        players.push({
          posThen: beforeSleep.pos,
          posNow: media.currentTime,
          rate: media.playbackRate,
        });
      }
      if (unwatchedGapMs({ at, since: lastHeartbeatAt, players }) <= SUSPENDED_MS) return;

      // Moved before the Events are written, so a `PLAY` here cannot be read as
      // a second suspension by whatever runs next.
      const confirmedAt = lastHeartbeatAt;
      lastHeartbeatAt = at;

      for (const entry of tracked.values()) {
        if (!isOpen(entry.viewId)) continue;
        apply(capture, {
          type: "PAUSE",
          at: confirmedAt,
          viewId: entry.viewId,
          // The position at that beat, not the one on screen now: the media may
          // have crept forward during the gap, and where it got to is not
          // something this frame watched.
          pos: capture.lastSampleSnapshot[entry.viewId]?.pos,
        });
        schedulePausedOut(entry.viewId);
      }
      for (const [media, entry] of tracked) {
        if (!isOpen(entry.viewId) || !isAdvancing(media)) continue;
        apply(capture, { type: "PLAY", at, viewId: entry.viewId, pos: media.currentTime });
        cancelPausedOut(entry.viewId);
        entry.pos = media.currentTime;
      }
      persistAll(true);
    }

    function tick() {
      refreshBindingIfUrlChanged();
      const at = Date.now();
      noticeWake(at);
      const visible = document.visibilityState === "visible";
      bootstrapUntrackedPlayers(at, visible);
      for (const [media, entry] of [...tracked]) {
        if (isOpen(entry.viewId)) refresh(media, { at, pos: media.currentTime });
      }

      // One View, one sample per beat. Two elements can share a View on a frame
      // with an Adapter — the pre-roll ad and the video it interrupted — and
      // sampling both would report two positions for one video, five seconds
      // apart on the App's side. The player that is actually advancing is the
      // one whose position means anything.
      const sampled = new Set();
      for (const media of advancingFirst()) {
        const entry = tracked.get(media);
        if (!entry || !isOpen(entry.viewId) || sampled.has(entry.viewId)) continue;
        sampled.add(entry.viewId);
        apply(capture, {
          type: "SAMPLE",
          at,
          viewId: entry.viewId,
          pos: media.currentTime,
          playing: isAdvancing(media),
          visible,
        });
      }
      lastHeartbeatAt = at;
      persistAll(true);
      ensureTimer();
    }

    /**
     * Safety net: if a player resumes after its View was auto-closed and the
     * page fires no fresh media event we can catch, the next heartbeat still
     * discovers it and re-opens capture without a page reload.
     */
    function bootstrapUntrackedPlayers(at, visible) {
      let bootstrapped = false;
      for (const media of document.querySelectorAll("video, audio")) {
        if (tracked.has(media)) continue;
        if (!wantsToPlay(media)) continue;
        const entry = ensureView(media, {
          kind: "sample",
          media,
          at,
          pos: media.currentTime,
          rate: media.playbackRate,
          visible,
          paused: media.paused,
          ended: media.ended,
          readyState: media.readyState,
        });
        if (!entry) continue;
        apply(capture, {
          type: "SAMPLE",
          at,
          viewId: entry.viewId,
          pos: media.currentTime,
          playing: isAdvancing(media),
          visible,
        });
        bootstrapped = true;
      }
      return bootstrapped;
    }

    /** Every tracked player, the ones actually moving first. */
    function advancingFirst() {
      const players = [...tracked.keys()];
      return [...players.filter((media) => isAdvancing(media)), ...players.filter((media) => !isAdvancing(media))];
    }

    // --- One media element, one View ----------------------------------------------

    function isNetflixWatchUrl(href = location.href) {
      try {
        const url = new URL(href);
        return url.hostname.endsWith("netflix.com") && /(?:^|\/)watch\/\d+/.test(url.pathname);
      } catch {
        return false;
      }
    }

    /** This element's own disambiguation key, minted once and kept. */
    function slotKeyFor(media) {
      if (!slotKeys.has(media)) slotKeys.set(media, `slot-${nextSlot++}`);
      return slotKeys.get(media);
    }

    /** The View for this element, opening one if it has none (or has out-lived it). */
    function ensureView(media, fact) {
      const existing = tracked.get(media);
      if (existing && isOpen(existing.viewId)) return existing;

      // A page with no Adapter has nothing reliable to say a tiny or
      // invisible element is a real player rather than an ad network's
      // viewability pixel — a `<video>` rendered at a couple of CSS pixels,
      // or hidden outright, plays for real but nobody is looking at it. An
      // Adapter-bound frame is trusted; on a frame with no Adapter, that
      // shape opens no View at all.
      if (!bound.adapter && !isVisiblyPlayable(media)) return null;

      // A `/watch/<id>` Netflix URL with no bound Adapter is almost always a
      // stale bind decision from just before navigation settled. Rebind once
      // right here, before deciding this element is ineligible.
      if (!bound.adapter && isNetflixWatchUrl() && !forcingNetflixRebind) {
        forcingNetflixRebind = true;
        try {
          rebind();
        } finally {
          forcingNetflixRebind = false;
        }
      }

      // On a site that ships an Adapter, "no Adapter bound" can mean either
      // "this site has no Adapter" (generic fallback allowed) or "this site's
      // Adapter looked at this URL and said it names no video" (generic
      // fallback forbidden: home-feed hover previews are not Views).
      if (!bound.adapter && bound.adapterCovered) return null;

      // Two players in one frame are two videos — unless an Adapter is bound,
      // in which case they are the pre-roll ad and the video it interrupted,
      // and the Adapter says both of them are the one video this page is
      // showing.
      const disambiguate = !bound.adapter && hasOpenView();
      const header = describe(media, { disambiguate });

      // On a frame with an Adapter, an element reporting a video the frame
      // already has open joins that View rather than opening a rival one: the
      // ad and the video it interrupts are one watch, not two. With no Adapter
      // there is nothing that reliable to go on, so each element keeps its own
      // View and two identical players on one page stay two Views.
      //
      // For YouTube Shorts and similar feeds, multiple <video> elements exist
      // simultaneously (current short + preloaded adjacent shorts). When multiple
      // elements for the same video fire loadedmetadata nearly simultaneously, check
      // both already-tracked views and pending opens to ensure they all share one View.
      const sharing = bound.adapter
        ? [...tracked.values()].find((open) => open.key === header.videoId && isOpen(open.viewId)) ||
          (pendingOpens.has(header.videoId) ? { viewId: pendingOpens.get(header.videoId) } : undefined)
        : undefined;
      
      const entry = {
        viewId: sharing?.viewId ?? ids.uuidv4(),
        key: header.videoId,
        pos: fact.pos || 0,
        disambiguate,
        // The media this View is about, so a player handed a different video
        // before the router notices can be caught — see `reportMetadata`.
        src: media.currentSrc || "",
      };
      
      if (!sharing) {
        // Mark this video as having an open View being created, so subsequent
        // simultaneous elements for the same video will share it.
        pendingOpens.set(header.videoId, entry.viewId);
        debugTrace("open", {
          viewId: entry.viewId,
          videoId: header.videoId,
          contentFormat: header.contentFormat,
          title: header.title ?? null,
          author: header.author ?? null,
          durationSec: header.durationSec ?? null,
          metadataSource: header.metadataSource ?? null,
          adapterId: header.adapterId ?? null,
        });
        apply(capture, { type: "OPEN", at: fact.at, viewId: entry.viewId, view: header });
      }

      tracked.set(media, entry);
      // `pendingOpens` is only for the tiny race while a View is being born.
      // Once this element is tracked, future same-video joins should come from
      // `tracked` itself; leaving the pending pointer behind can route a resume
      // back to a closed View id.
      if (pendingOpens.get(header.videoId) === entry.viewId) pendingOpens.delete(header.videoId);
      scheduleMetadata();
      return entry;
    }

    /** Is any element in this frame already holding a View open? */
    function hasOpenView() {
      for (const entry of tracked.values()) if (isOpen(entry.viewId)) return true;
      return false;
    }

    /** Re-read the element: a new video id ends the View, new metadata amends it. */
    function refresh(media, fact) {
      const entry = tracked.get(media);
      if (!entry || !isOpen(entry.viewId)) return;
      const header = describe(media, entry);

      if (header.videoId !== entry.key) {
        const viewId = ids.uuidv4();
        // Clean up pending opens for the old video since it's ending
        pendingOpens.delete(entry.key);
        // At the exact boundary between Shorts, mediaSession often reports a
        // mixed snapshot (new title with previous author, or vice versa). A
        // wrong carry-over is worse than a brief blank, so boundary-opened
        // Views start without prose when that prose came from mediaSession;
        // the debounced metadata pass fills it once sources settle.
        const boundaryHeader =
          header.metadataSource === "mediaSession"
            ? { ...header, title: null, author: null, durationSec: null }
            : header;
        debugTrace("change_video", {
          fromViewId: entry.viewId,
          toViewId: viewId,
          fromVideoId: entry.key,
          toVideoId: header.videoId,
          title: header.title ?? null,
          author: header.author ?? null,
          durationSec: header.durationSec ?? null,
          metadataSource: header.metadataSource ?? null,
          adapterId: header.adapterId ?? null,
          boundaryProseCleared: boundaryHeader !== header,
          boundaryDurationCleared: boundaryHeader !== header,
        });
        apply(capture, {
          type: "CHANGE_VIDEO",
          at: fact.at,
          pos: entry.pos,
          fromViewId: entry.viewId,
          viewId,
          view: boundaryHeader,
        });
        // Every element that was on the old video moves across together, or the
        // ad player would open a second View against the video that replaced it.
        for (const [other, otherEntry] of [...tracked]) {
          if (otherEntry.viewId !== entry.viewId) continue;
          tracked.set(other, {
            ...otherEntry,
            viewId,
            key: header.videoId,
            pos: 0,
            src: other.currentSrc || "",
          });
        }
      } else if (!entry.src) {
        // A player built before its media was attached: the first source it is
        // given is the one this View is about.
        entry.src = media.currentSrc || "";
      }
      scheduleMetadata();
    }

    /**
     * Everything this frame can say about the media right now: the bound
     * Adapter, `mediaSession`, the generic fallback and the element itself, put
     * in their order by `metadata.js`.
     */
    function describe(media, { disambiguate = false } = {}) {
      const generic = readGeneric({
        location,
        document,
        mediaSrc: media.currentSrc || media.src || "",
        duration: media.duration,
        disambiguate,
        disambiguateKey: disambiguate ? slotKeyFor(media) : null,
      });
      return merge({
        router: {
          service: bound.service,
          adapterId: bound.adapterId,
          embedded: meta.isEmbedded({
            isTopFrame: window === window.top,
            frameUrl: location.href,
            topUrl: topFrameUrl(),
          }),
        },
        adapter: bound.adapter?.read() ?? null,
        session: meta.fromMediaSession(navigator.mediaSession?.metadata),
        element: { durationSec: generic.durationSec },
        generic: { ...generic, videoId: videoIdFor(generic.videoIdSource) },
      });
    }

    /** The generic video id: `sha1:` of the page address, per the schema. */
    function videoIdFor(source) {
      if (!idCache.has(source)) idCache.set(source, `sha1:${ids.sha1Hex(source)}`);
      return idCache.get(source);
    }

    function topFrameUrl() {
      if (window === window.top) return location.href;
      try {
        // Readable only when the ancestor is same-origin; unreadable is itself
        // the answer, and `isEmbedded` reads it as third party.
        return window.top.location.href;
      } catch {
        return location.ancestorOrigins?.[location.ancestorOrigins.length - 1] ?? null;
      }
    }

    // --- Metadata, once it has stopped moving --------------------------------------

    /** Ask for a report. Every fresh ask restarts the wait. */
    function scheduleMetadata() {
      if (metaTimer !== null) clearTimeout(metaTimer);
      metaTimer = setTimeout(reportMetadata, META_DEBOUNCE_MS);
    }

    /**
     * One `metadataChange` per open View, covering everything that moved.
     *
     * Never a video id: a new id is a View boundary and `refresh` has already
     * dealt with it, so by the time this runs the id is either unchanged or
     * already the new View's own. A `contentFormat` that moved on its own — a
     * livestream turning into the replay of itself, same id — is reported here
     * and the View carries straight on.
     *
     * A player whose element has already been handed the next video is skipped:
     * its id is unchanged only because the router has not caught up yet, and
     * what the page says now names the video coming, not the one being watched.
     * The View keeps the name it was opened with until its own boundary lands.
     */
    function reportMetadata() {
      clearTimeout(metaTimer);
      metaTimer = null;
      const at = Date.now();
      const reported = new Set();

      for (const [media, entry] of [...tracked]) {
        if (!isOpen(entry.viewId) || reported.has(entry.viewId)) continue;
        // Read live rather than remembered: this report may have been scheduled
        // before the element was handed the next video.
        if (meta.isMediaSwap({ openedWith: entry.src, current: media.currentSrc })) continue;
        reported.add(entry.viewId);

        const header = describe(media, entry);
        const current = capture.views[entry.viewId];
        let changed = meta.metadataDiff(current, {
          title: header.title,
          author: header.author,
          durationSec: header.durationSec,
          contentFormat: header.contentFormat,
        });
        if (!changed) continue;

        // Shorts immediately after a boundary often carry a mixed mediaSession
        // snapshot (new title, old author). During that short settle window,
        // keep only non-prose changes and wait for a later, stable update.
        if (
          current?.contentFormat === "short" &&
          header.metadataSource === "mediaSession" &&
          at - (current.startedAt ?? at) < SHORTS_MEDIASESSION_SETTLE_MS
        ) {
          const filtered = { ...changed };
          delete filtered.title;
          delete filtered.author;
          if (Object.keys(filtered).length === 0) {
            debugTrace("metadata_change_suppressed", {
              viewId: entry.viewId,
              videoId: current?.videoId ?? null,
              settleMs: SHORTS_MEDIASESSION_SETTLE_MS,
              changed,
              next: {
                title: header.title ?? null,
                author: header.author ?? null,
                durationSec: header.durationSec ?? null,
                contentFormat: header.contentFormat ?? null,
                metadataSource: header.metadataSource ?? null,
                adapterId: header.adapterId ?? null,
              },
            });
            continue;
          }
          changed = filtered;
        }

        debugTrace("metadata_change", {
          viewId: entry.viewId,
          videoId: capture.views[entry.viewId]?.videoId ?? null,
          changed,
          next: {
            title: header.title ?? null,
            author: header.author ?? null,
            durationSec: header.durationSec ?? null,
            contentFormat: header.contentFormat ?? null,
            metadataSource: header.metadataSource ?? null,
            adapterId: header.adapterId ?? null,
          },
        });

        apply(capture, {
          type: "META",
          at,
          viewId: entry.viewId,
          changed,
          metadataSource: header.metadataSource,
          adapterId: header.adapterId,
        });
      }
      persistAll();
    }

    // --- Applying and persisting -----------------------------------------------------

    function isOpen(viewId) {
      return capture.views[viewId]?.open === true;
    }

    function anyOpenViewId() {
      return capture.order.find((id) => capture.views[id].open);
    }

    function schedulePausedOut(viewId) {
      cancelPausedOut(viewId);
      pausedOutTimers.set(
        viewId,
        setTimeout(() => {
          pausedOutTimers.delete(viewId);
          if (!isOpen(viewId)) return;

          const players = [...tracked].filter(([, entry]) => entry.viewId === viewId);
          if (players.some(([media]) => wantsToPlay(media))) return;

          apply(capture, {
            type: "VIEW_ENDED",
            at: Date.now(),
            viewId,
            pos: positionOf(viewId) ?? capture.lastSampleSnapshot[viewId]?.pos,
            reason: "paused-out",
          });
          persistAll(true);
          ensureTimer();
        }, PAUSED_OUT_MS),
      );
    }

    function cancelPausedOut(viewId) {
      const timer = pausedOutTimers.get(viewId);
      if (timer !== undefined) clearTimeout(timer);
      pausedOutTimers.delete(viewId);
    }

    function act(fact, action, flush = false) {
      const entry = tracked.get(fact.media);
      if (!entry) return;
      apply(capture, { ...action, at: fact.at, viewId: entry.viewId, pos: fact.pos });
      entry.pos = fact.pos;

      if (action.type === "PAUSE") schedulePausedOut(entry.viewId);
      else if (action.type === "PLAY" || action.type === "VIEW_ENDED") cancelPausedOut(entry.viewId);

      if (flush) persistAll(true);
    }

    /**
     * Write every View's un-written Events (and its header) in one storage call,
     * then — when there is something worth sending — wake the worker.
     */
    function persistAll(flush = false) {
      let writes = null;
      for (const viewId of [...capture.order]) {
        const view = capture.views[viewId];
        if (persisted.get(viewId) === view._seq) continue;
        writes = Object.assign(
          writes ?? {},
          buffer.writesFor(view, { runId, fromSeq: persisted.get(viewId) ?? 0 }),
        );
        persisted.set(viewId, view._seq);
        // A closed View is the buffer's problem now: the worker deletes its keys
        // once the App has Ack'd them.
        if (!view.open) forget(viewId);
      }
      if (!writes && !flush) return;

      writing = writing
        .then(() => (writes ? chrome.storage.local.set(writes) : null))
        .then(() => (flush ? ask({ type: "flush" }) : null))
        .catch(stopOnTeardown);
    }

    /** Drop a closed View from this frame's working set; the buffer still has it. */
    function forget(viewId) {
      cancelPausedOut(viewId);
      for (const [videoId, pendingViewId] of pendingOpens) {
        if (pendingViewId === viewId) pendingOpens.delete(videoId);
      }
      for (const [media, entry] of tracked) {
        if (entry.viewId === viewId) tracked.delete(media);
      }
      persisted.delete(viewId);
      delete capture.views[viewId];
      delete capture.lastFlushAckSeq[viewId];
      delete capture.lastSampleSnapshot[viewId];
      capture.order = capture.order.filter((id) => id !== viewId);
      if (capture.activeViewId === viewId) capture.activeViewId = null;
    }

    function stopOnTeardown() {
      // The extension was reloaded or the browser is shutting down: stop the
      // cadence rather than throwing on every tick.
      if (!chrome.runtime?.id) {
        if (sampleTimer !== null) {
          clearInterval(sampleTimer);
          sampleTimer = null;
        }
        if (discoveryTimer !== null) {
          clearInterval(discoveryTimer);
          discoveryTimer = null;
        }
        clearTimeout(metaTimer);
        metaTimer = null;
      }
    }
  }
})();
