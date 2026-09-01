// The page helper. Runs in every frame of every page, watches the media
// elements it finds there, and turns what they do into raw Events.
//
// It owns the capture cadence end to end: the 5-second `sample` timer, the
// per-View `seq`, and the on-disk buffer. The background worker owns only the
// POST, the Ack and the prune — so an evicted worker costs a little latency,
// never a lost Event.
//
// Nothing here interprets anything. `hidden` is recorded as `hidden`, a muted
// PiP player is recorded exactly like any other; Segments, Background audio and
// Watched time are the App's job.
//
// This script lands in every frame of every page, including the dozens of tiny
// ad frames that will never hold a player, so it starts as nothing but a
// handful of listeners. The modules, the handshake with the worker and the
// session are all built on the first media event the frame actually sees.

(() => {
  const SAMPLE_MS = 5000;

  /** Media events don't bubble, so these are capture-phase listeners on the root. */
  const MEDIA_EVENTS = [
    "loadedmetadata", "durationchange", "play", "playing", "pause", "ended",
    "ratechange", "seeked", "enterpictureinpicture", "leavepictureinpicture",
  ];

  /** The running capture context, once a player has shown up. */
  let helper = null;
  let booting = null;
  const queued = [];

  for (const type of MEDIA_EVENTS) {
    document.addEventListener(
      type,
      (event) => {
        if (!(event.target instanceof HTMLMediaElement)) return;
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

  function boot() {
    // A failed boot resets, so the next media event tries again — the worker may
    // simply have been mid-restart.
    return (booting ??= start().catch(() => {
      booting = null;
      return null;
    }));
  }

  async function start() {
    const load = (path) => import(chrome.runtime.getURL(path));
    const [capture, buffer, meta, ids] = await Promise.all([
      load("src/capture.js"),
      load("src/buffer.js"),
      load("src/identify.js"),
      load("src/ids.js"),
    ]);

    // `hello` doubles as a barrier: the worker answers only once it has closed
    // whatever a previous browser run left open, so no View we write now can be
    // mistaken for a crashed one.
    const hello = await ask({ type: "hello" });
    if (!hello) throw new Error("the WatchLogs worker did not answer");

    helper = makeHelper({ capture, buffer, meta, ids, hello });
    for (const fact of queued.splice(0)) helper.handle(fact);
    return helper;
  }

  function ask(message) {
    return chrome.runtime.sendMessage(message).catch(() => null);
  }

  // --- The capture context ------------------------------------------------------

  function makeHelper({ capture, buffer, meta, ids, hello }) {
    const { apply, initSession } = capture;
    const runId = hello.runId;
    const session = initSession(Date.now(), { tabId: hello.tabId ?? 0 });
    // A tab opened in the background starts hidden; without this the first
    // `visible` would look like a transition that never happened.
    session.tabVisible = document.visibilityState === "visible";

    /** media element -> { viewId, idSource, pos } */
    const tracked = new Map();
    /** viewId -> the highest seq already on disk */
    const persisted = new Map();
    const idCache = new Map();
    let sampleTimer = null;
    let writing = Promise.resolve();

    return { handle, note, setVisible, endAll };

    // --- What just happened -----------------------------------------------------

    function handle(fact) {
      const entry = ensureView(fact.media, fact);
      if (!entry) return;

      switch (fact.kind) {
        case "loadedmetadata":
        case "durationchange":
          refresh(fact.media, fact);
          break;
        case "play":
        case "playing":
          act(fact, { type: "PLAY" });
          break;
        case "pause":
          act(fact, { type: "PAUSE" }, true);
          break;
        case "ended":
          act(fact, { type: "MEDIA_ENDED" }, true);
          break;
        case "ratechange":
          act(fact, { type: "RATE", rate: fact.rate });
          break;
        case "seeked":
          act(fact, { type: "SEEKED", from: entry.pos, to: fact.pos });
          break;
        case "enterpictureinpicture":
          act(fact, { type: "PIP_ENTER" });
          break;
        case "leavepictureinpicture":
          act(fact, { type: "PIP_LEAVE" });
          break;
      }
      persistAll();
      ensureTimer();
    }

    function note(media, pos) {
      const entry = tracked.get(media);
      if (entry) entry.pos = pos;
    }

    function setVisible(visible) {
      apply(session, {
        type: visible ? "SHOW" : "HIDE",
        at: Date.now(),
        viewId: anyOpenViewId(),
      });
      persistAll(true);
    }

    /**
     * A View that outlives its page is a View nobody will ever close, so say so
     * on the way out. Best-effort: if the frame dies before the write lands, the
     * View is recovered from its last `sample` on the next browser run.
     */
    function endAll(reason) {
      for (const [media, entry] of tracked) {
        if (!isOpen(entry.viewId)) continue;
        apply(session, {
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
      const playing = [...tracked.keys()].some(isPlaying);
      if (playing && sampleTimer === null) {
        sampleTimer = setInterval(tick, SAMPLE_MS);
      } else if (!playing && sampleTimer !== null) {
        clearInterval(sampleTimer);
        sampleTimer = null;
      }
    }

    function tick() {
      const at = Date.now();
      const visible = document.visibilityState === "visible";
      for (const [media, entry] of [...tracked]) {
        if (!isOpen(entry.viewId)) continue;
        refresh(media, { at, pos: media.currentTime });
        apply(session, {
          type: "SAMPLE",
          at,
          viewId: tracked.get(media)?.viewId,
          pos: media.currentTime,
          playing: isPlaying(media),
          visible,
        });
      }
      persistAll(true);
      ensureTimer();
    }

    // --- One media element, one View ----------------------------------------------

    /** The View for this element, opening one if it has none (or has out-lived it). */
    function ensureView(media, fact) {
      const existing = tracked.get(media);
      if (existing && isOpen(existing.viewId)) return existing;

      const header = describe(media);
      const viewId = ids.uuidv4();
      apply(session, { type: "OPEN", at: fact.at, viewId, view: header });
      const entry = { viewId, idSource: header.videoIdSource, pos: fact.pos || 0 };
      tracked.set(media, entry);
      readMetadata(media, fact.at);
      return entry;
    }

    /** Re-read the element: a new video id ends the View, new metadata amends it. */
    function refresh(media, fact) {
      const entry = tracked.get(media);
      if (!entry || !isOpen(entry.viewId)) return;
      const header = describe(media);

      if (header.videoIdSource !== entry.idSource) {
        const viewId = ids.uuidv4();
        apply(session, {
          type: "CHANGE_VIDEO",
          at: fact.at,
          pos: entry.pos,
          fromViewId: entry.viewId,
          viewId,
          view: header,
        });
        tracked.set(media, { viewId, idSource: header.videoIdSource, pos: 0 });
      }
      readMetadata(media, fact.at);
    }

    /** What this frame can say about the media without an Adapter. */
    function describe(media) {
      const header = meta.identify({
        frameUrl: location.href,
        topUrl: topFrameUrl(),
        isTopFrame: window === window.top,
        mediaSrc: media.currentSrc || media.src || "",
        duration: media.duration,
      });
      return { ...header, videoId: videoIdFor(header.videoIdSource) };
    }

    /** The generic video id: `sha1:` of the normalised URL, per the schema. */
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

    /** Whatever `mediaSession` and the element itself now know. */
    function readMetadata(media, at) {
      const entry = tracked.get(media);
      if (!entry || !isOpen(entry.viewId)) return;
      const view = session.views[entry.viewId];

      const fromSession = meta.fromMediaSession(navigator.mediaSession?.metadata);
      const changed = meta.metadataDiff(view, {
        ...fromSession,
        durationSec: meta.durationOf(media.duration),
      });
      if (!changed) return;

      // Only claim `mediaSession` as the source when it is what moved.
      const source = Object.keys(fromSession).some((field) => field in changed)
        ? "mediaSession"
        : view.metadataSource;
      apply(session, { type: "META", at, viewId: entry.viewId, changed, metadataSource: source });
    }

    // --- Applying and persisting -----------------------------------------------------

    function isPlaying(media) {
      return !media.paused && !media.ended;
    }

    function isOpen(viewId) {
      return session.views[viewId]?.open === true;
    }

    function anyOpenViewId() {
      return session.order.find((id) => session.views[id].open);
    }

    function act(fact, action, flush = false) {
      const entry = tracked.get(fact.media);
      if (!entry) return;
      apply(session, { ...action, at: fact.at, viewId: entry.viewId, pos: fact.pos });
      entry.pos = fact.pos;
      if (flush) persistAll(true);
    }

    /**
     * Write every View's un-written Events (and its header) in one storage call,
     * then — when there is something worth sending — wake the worker.
     */
    function persistAll(flush = false) {
      let writes = null;
      for (const viewId of [...session.order]) {
        const view = session.views[viewId];
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
      delete session.views[viewId];
      delete session.lastFlushAckSeq[viewId];
      delete session.lastSampleSnapshot[viewId];
      session.order = session.order.filter((id) => id !== viewId);
      if (session.activeViewId === viewId) session.activeViewId = null;
    }

    function stopOnTeardown() {
      // The extension was reloaded or the browser is shutting down: stop the
      // cadence rather than throwing on every tick.
      if (!chrome.runtime?.id && sampleTimer !== null) {
        clearInterval(sampleTimer);
        sampleTimer = null;
      }
    }
  }
})();
