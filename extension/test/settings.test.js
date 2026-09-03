import test from "node:test";
import assert from "node:assert/strict";
import { capturesPrivateWindowsForHello } from "../src/settings.js";

test("a successful App setting governs the hello private-window decision", () => {
  assert.equal(
    capturesPrivateWindowsForHello({ ok: true, capturePrivateWindows: true }),
    true,
  );
  assert.equal(
    capturesPrivateWindowsForHello({ ok: true, capturePrivateWindows: false }),
    false,
  );
});

test("an unreachable App disables private-window capture", () => {
  assert.equal(capturesPrivateWindowsForHello(null), false);
  assert.equal(capturesPrivateWindowsForHello({ ok: false, capturePrivateWindows: true }), false);
});
