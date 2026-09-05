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

  /**
   * Media event -> what it means, in one table so the two can't drift apart.
   * `action` is null where the event only means "re-read the element".
   * `flush` marks the ones worth waking the worker for straight away, rather
   * than waiting for the next 5-second beat.
   */
  const MEDIA_EVENTS = {
    loadedmetadata: {},
    durationchange: {},
    play: { action: () => ({ type: "PLAY" }) },
    playing: { action: () => ({ type: "PLAY" }) },
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

    /** media element -> { viewId, key, pos, disambiguate } */
    const tracked = new Map();
    /** viewId -> the highest seq already on disk */
    const persisted = new Map();
    const idCache = new Map();
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
      unwatchMetadata = watchMetadata();
      const at = Date.now();
      for (const [media, entry] of [...tracked]) {
        if (isOpen(entry.viewId)) refresh(media, { at, pos: media.currentTime });
      }
    }

    return { handle, note, setVisible, endAll, noticeWake };

    // --- What just happened -----------------------------------------------------

    function handle(fact) {
      noticeWake(fact.at);
      const entry = ensureView(fact.media, fact);
      if (!entry) return;

      const meaning = MEDIA_EVENTS[fact.kind];
      if (meaning.action) act(fact, meaning.action(fact, entry), meaning.flush);
      else refresh(fact.media, fact);
      persistAll();
      ensureTimer();
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
        apply(capture, {
          type: "VIEW_ENDED",
          at: Date.now(),
          viewId: entry.viewId,
          pos: media.currentTime,
          reason,
        });
      }
      persistAll(true);
    }

    // --- The 5-second heartbeat --------------------------------------------------

    function ensureTimer() {
      const playing = [...tracked.keys()].some((media) => isAdvancing(media));
      if (playing && sampleTimer === null) {
        sampleTimer = setInterval(tick, SAMPLE_MS);
        lastHeartbeatAt = Date.now();
      } else if (!playing && sampleTimer !== null) {
        clearInterval(sampleTimer);
        sampleTimer = null;
        lastHeartbeatAt = null;
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
      }
      for (const [media, entry] of tracked) {
        if (!isOpen(entry.viewId) || !isAdvancing(media)) continue;
        apply(capture, { type: "PLAY", at, viewId: entry.viewId, pos: media.currentTime });
        entry.pos = media.currentTime;
      }
      persistAll(true);
    }

    function tick() {
      const at = Date.now();
      noticeWake(at);
      const visible = document.visibilityState === "visible";
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

    /** Every tracked player, the ones actually moving first. */
    function advancingFirst() {
      const players = [...tracked.keys()];
      return [...players.filter((media) => isAdvancing(media)), ...players.filter((media) => !isAdvancing(media))];
    }

    // --- One media element, one View ----------------------------------------------

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
      const sharing = bound.adapter
        ? [...tracked.values()].find((open) => open.key === header.videoId && isOpen(open.viewId))
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
      if (!sharing) apply(capture, { type: "OPEN", at: fact.at, viewId: entry.viewId, view: header });
      tracked.set(media, entry);
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
        apply(capture, {
          type: "CHANGE_VIDEO",
          at: fact.at,
          pos: entry.pos,
          fromViewId: entry.viewId,
          viewId,
          view: header,
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
        const changed = meta.metadataDiff(capture.views[entry.viewId], {
          title: header.title,
          author: header.author,
          durationSec: header.durationSec,
          contentFormat: header.contentFormat,
        });
        if (!changed) continue;

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

    function act(fact, action, flush = false) {
      const entry = tracked.get(fact.media);
      if (!entry) return;
      apply(capture, { ...action, at: fact.at, viewId: entry.viewId, pos: fact.pos });
      entry.pos = fact.pos;
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
      if (!chrome.runtime?.id && sampleTimer !== null) {
        clearInterval(sampleTimer);
        sampleTimer = null;
        clearTimeout(metaTimer);
        metaTimer = null;
      }
    }
  }
})();
