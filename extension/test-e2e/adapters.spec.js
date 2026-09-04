// The Adapters against real saved Service pages.
//
// The node suite pins what each Adapter *decides*; this pins that its selectors
// still find anything, which is the half a fake document cannot prove. The
// YouTube pages here are genuine captures — a real watch page, a real Short, a
// real livestream — taken by `fixtures/capture-pages.mjs` after the page's own
// scripts had finished building it, then stripped of those scripts. Netflix
// cannot be captured at all (a watch page needs a logged-in subscriber), so its
// two fixtures are hand-built and say so at the top of each file.
//
// No extension is loaded here and no App is involved: each test opens a saved
// page in a plain tab, imports the Adapter into it from the same origin, hands
// it that page's document and a URL of its own choosing, and reads the result.
// That last part matters — a fixture served from 127.0.0.1 has the wrong
// address, and the address is where an Adapter gets the id.
//
// Run with `npm run test:e2e`. When a fixture goes stale, re-capture rather
// than hand-editing: `node test-e2e/fixtures/capture-pages.mjs`.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { chromium } from "playwright";
import { startStubServer } from "./stub-server.mjs";

let server;
let browser;
let page;

before(async () => {
  server = await startStubServer();
  browser = await chromium.launch();
  page = await browser.newPage();
});

after(async () => {
  await browser?.close();
  await server?.close();
});

/** Open a saved page, then read it as if it had been served from `href`. */
async function readOn(fixture, module, exportName, href) {
  await page.goto(new URL(fixture, server.baseUrl).href);
  return page.evaluate(
    async ([modulePath, name, url]) => {
      const adapter = (await import(modulePath))[name];
      return {
        matches: adapter.matches(new URL(url)),
        snapshot: adapter.create({ location: { href: url }, document }).read(),
      };
    },
    [`/src/adapters/${module}.js`, exportName, href],
  );
}

const youtube = (fixture, href) => readOn(`/youtube/${fixture}.html`, "youtube", "YouTubeAdapter", href);
const netflix = (fixture, href) => readOn(`/netflix/${fixture}.html`, "netflix", "NetflixAdapter", href);

test("a real watch page gives up its id, title and channel", { timeout: 30_000 }, async () => {
  const { matches, snapshot } = await youtube("watch", "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
  assert.equal(matches, true);
  assert.equal(snapshot.videoId, "dQw4w9WgXcQ");
  assert.equal(snapshot.contentFormat, "standard");
  assert.match(snapshot.title, /Never Gonna Give You Up/);
  assert.equal(snapshot.author, "Rick Astley");
  assert.equal(snapshot.confidence, "high");
});

test("a real livestream reads as live from the path and from the page", { timeout: 30_000 }, async () => {
  const fromPath = await youtube("live", "https://www.youtube.com/live/jfKfPfyJRdk");
  assert.equal(fromPath.snapshot.videoId, "jfKfPfyJRdk");
  assert.equal(fromPath.snapshot.contentFormat, "live");
  assert.equal(fromPath.snapshot.author, "Lofi Girl");

  // The same broadcast reached by its watch URL has no live *path* to go on, so
  // this is the schema.org marker doing the work.
  const fromMarker = await youtube("live", "https://www.youtube.com/watch?v=jfKfPfyJRdk");
  assert.equal(fromMarker.snapshot.contentFormat, "live");
});

test("a real Short is a short, with the Short's own title element", { timeout: 30_000 }, async () => {
  const { snapshot } = await youtube("shorts", "https://www.youtube.com/shorts/68UcmJtcChs");
  assert.equal(snapshot.videoId, "68UcmJtcChs");
  assert.equal(snapshot.contentFormat, "short");
  assert.ok(snapshot.title, "expected the Short's title, not the watch page's empty h1");
  assert.ok(snapshot.author, "expected a channel name");
  assert.equal(snapshot.confidence, "high");
});

// An embed that has not been played yet is a shell: the player draws its title
// bar on first play, and this fixture was captured before that. Which is the
// case worth pinning — the id still has to survive on a page with no metadata
// at all, and the Adapter has to admit it is not confident.
test("a real embed keeps the id and admits it found nothing else", { timeout: 30_000 }, async () => {
  const { snapshot } = await youtube("embed", "https://www.youtube.com/embed/dQw4w9WgXcQ");
  assert.equal(snapshot.videoId, "dQw4w9WgXcQ");
  assert.equal(snapshot.embedded, true);
  assert.equal(snapshot.confidence, "low");
});

test("a real channel page and YouTube Music are declined", { timeout: 30_000 }, async () => {
  const channel = await youtube("channel", "https://www.youtube.com/@RickAstleyYT");
  assert.equal(channel.matches, false);
  const music = await youtube("music", "https://music.youtube.com/watch?v=dQw4w9WgXcQ");
  assert.equal(music.matches, false);
});

test("the router binds these pages the way each Adapter asked", { timeout: 30_000 }, async () => {
  const cases = [
    ["/youtube/watch.html", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "youtube", "youtube"],
    ["/youtube/shorts.html", "https://www.youtube.com/shorts/68UcmJtcChs", "youtube", "youtube"],
    ["/youtube/channel.html", "https://www.youtube.com/@RickAstleyYT", null, "youtube.com"],
    ["/youtube/music.html", "https://music.youtube.com/watch?v=abc", null, "youtube.com"],
    ["/netflix/series.html", "https://www.netflix.com/watch/81234567", "netflix", "netflix"],
    ["/netflix/film.html", "https://www.netflix.com/browse", null, "netflix.com"],
  ];
  for (const [fixture, href, adapterId, service] of cases) {
    await page.goto(new URL(fixture, server.baseUrl).href);
    const bound = await page.evaluate(async (url) => {
      const { bindAdapter } = await import("/src/adapters/router.js");
      const { adapterId, service } = bindAdapter({ location: { href: url }, document });
      return { adapterId, service };
    }, href);
    assert.deepEqual(bound, { adapterId, service }, href);
  }
});

test("the Netflix player's title block reads as a series and as a film", { timeout: 30_000 }, async () => {
  const series = await netflix("series", "https://www.netflix.com/watch/81234567");
  assert.equal(series.snapshot.videoId, "81234567");
  assert.equal(series.snapshot.author, "Stranger Things");
  assert.equal(series.snapshot.title, "Stranger Things - Chapter Four: The Sauna Test");

  const film = await netflix("film", "https://www.netflix.com/watch/81444554");
  assert.equal(film.snapshot.author, "", "a film's author is known to be nothing");
  assert.equal(film.snapshot.title, "Glass Onion: A Knives Out Mystery");
});

test("the fallback reads a page nobody wrote an Adapter for", { timeout: 30_000 }, async () => {
  await page.goto(new URL("/player.html", server.baseUrl).href);
  const generic = await page.evaluate(async () => {
    const { readGeneric } = await import("/src/adapters/generic.js");
    return readGeneric({
      location: { href: "https://iplayer.bbc.co.uk/episode/m001?autoplay=1" },
      document,
      duration: 213,
    });
  });
  assert.equal(generic.service, "bbc.co.uk");
  assert.equal(generic.videoIdSource, "https://iplayer.bbc.co.uk/episode/m001");
  assert.equal(generic.contentFormat, "standard");
  assert.equal(generic.confidence, "fallback");
  assert.ok(generic.documentTitle, "expected the browser tab's title as the last rung");
});
