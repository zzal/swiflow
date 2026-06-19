// js-driver/test/regions/host.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { createGuestHost } from "../../swiflow-regions.js";
import fakeGuest from "./fixtures/fake-guest.js";

function makeHost() {
  const posted = [];
  const host = createGuestHost({
    post: (m) => posted.push(m),
    importGuest: async (_source) => fakeGuest, // bypass real import()
    raf: () => 0, // inert frame loop; the real schedulers are tested separately
  });
  return { host, posted };
}

// A guest that just counts frames, served through importGuest.
function tickHost() {
  let frames = 0;
  const host = createGuestHost({
    post: () => {},
    importGuest: async () => () => ({ frame: () => { frames++; }, destroy() {} }),
    // no raf/caf: node has no requestAnimationFrame, so the setTimeout fallback runs
  });
  const init = host.handle({ v: 1, kind: "init", payload: { source: "x", props: null, size: {} } }, {});
  return { host, init, frames: () => frames };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

describe("createGuestHost", () => {
  test("init imports the guest, emits ready, and forwards initial props", async () => {
    const { host, posted } = makeHost();
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: JSON.stringify({ count: 3 }), size: { w: 10, h: 10, dpr: 1 } } }, /*canvas*/ {});
    assert.ok(posted.some((m) => m.kind === "ready"));
    const events = posted.filter((m) => m.kind === "event").map((m) => JSON.parse(m.payload));
    assert.deepEqual(events[0], { kind: "init", count: 3 });
  });

  test("props/resize/destroy reach the guest", async () => {
    const { host, posted } = makeHost();
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: null, size: { w: 1, h: 1, dpr: 1 } } }, {});
    host.handle({ v: 1, kind: "props", payload: JSON.stringify({ count: 5 }) });
    host.handle({ v: 1, kind: "resize", payload: { w: 20, h: 30, dpr: 2 } });
    const ev = posted.filter((m) => m.kind === "event").map((m) => JSON.parse(m.payload));
    assert.deepEqual(ev.at(-1), { kind: "prop", count: 5 });
    host.handle({ v: 1, kind: "destroy", payload: null });
    const before = posted.length;
    host.handle({ v: 1, kind: "props", payload: JSON.stringify({ count: 9 }) });
    assert.equal(posted.length, before);
  });

  test("a guest factory that throws yields an error envelope, not a crash", async () => {
    const posted = [];
    const host = createGuestHost({
      post: (m) => posted.push(m),
      importGuest: async () => () => { throw new Error("boom"); },
    });
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: null, size: { w: 1, h: 1, dpr: 1 } } }, {});
    const err = posted.find((m) => m.kind === "error");
    assert.ok(err);
    assert.equal(err.payload.code, "init-failed");
  });

  test("falls back to setTimeout when requestAnimationFrame is absent", async () => {
    const { host, init, frames } = tickHost();
    await init;
    await sleep(60); // ~3-4 ticks at 16ms
    host.handle({ v: 1, kind: "destroy", payload: null }); // clearTimeout stops the loop
    assert.ok(frames() >= 2, `expected setTimeout-driven frames, got ${frames()}`);
  });

  test("pause cancels the pending frame; resume restarts it", async () => {
    const { host, init, frames } = tickHost();
    await init;
    await sleep(50);
    host.handle({ v: 1, kind: "pause", payload: null });
    const atPause = frames();
    await sleep(50);
    assert.equal(frames(), atPause, "no ticks while paused");
    host.handle({ v: 1, kind: "resume", payload: null });
    await sleep(50);
    host.handle({ v: 1, kind: "destroy", payload: null });
    assert.ok(frames() > atPause, "ticks resume after resume");
  });
});
