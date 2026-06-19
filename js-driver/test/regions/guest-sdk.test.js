import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { canvasGuest } from "../../swiflow-region-guest.js";

// Minimal fakes: the shim never draws itself — it only gets the 2D context and
// passes it through — so the ctx is an opaque marker.
function fakeCanvas() {
  const ctx2d = { _is: "ctx2d" };
  return { width: 0, height: 0, getContext: () => ctx2d, _ctx: ctx2d };
}
function fakeHost(size) {
  const events = [];
  return { emit: (e) => events.push(e), size, _events: events };
}

describe("canvasGuest — raster mode", () => {
  test("setup runs; initial resize fires with device dims; frame forwards ctx2d/dims/dt/fps", async () => {
    const calls = { setup: 0, resize: [], frame: [] };
    const factory = canvasGuest({
      async setup({ props }) { calls.setup++; return { props }; },
      resize(s, c) { calls.resize.push([c.width, c.height, c.dpr]); },
      frame(s, c) { calls.frame.push(c); },
    });
    const canvas = fakeCanvas();
    const guest = await factory(canvas, { a: 1 }, fakeHost({ w: 200, h: 100, dpr: 2 }));
    assert.equal(calls.setup, 1);
    assert.deepEqual(calls.resize, [[200, 100, 2]]);
    assert.equal(canvas.width, 200);   // raster buffer = device size
    assert.equal(canvas.height, 100);
    guest.frame(16);
    const f = calls.frame.at(-1);
    assert.equal(f.ctx2d, canvas._ctx);
    assert.equal(f.width, 200); assert.equal(f.height, 100); assert.equal(f.dpr, 2);
    assert.equal(f.dt, 16); assert.ok(f.fps > 0);
  });

  test("onResize fires resize only when device dims change", async () => {
    const sizes = [];
    const factory = canvasGuest({ async setup() { return {}; }, resize(s, c) { sizes.push([c.width, c.height]); }, frame() {} });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 100, h: 80, dpr: 1 }));
    guest.onResize(100, 80, 1); // no change
    guest.onResize(120, 80, 1); // change
    guest.onResize(120, 80, 1); // no change
    assert.deepEqual(sizes, [[100, 80], [120, 80]]); // initial + the one change
  });

  test("fps is a smoothed EMA of 1000/dt", async () => {
    let lastFps = 0;
    const factory = canvasGuest({ async setup() { return {}; }, frame(s, c) { lastFps = c.fps; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
    for (let i = 0; i < 10; i++) guest.frame(20); // 50 fps
    assert.equal(Math.round(lastFps), 50);
  });

  test("onProps and destroy reach the hooks", async () => {
    const seen = { props: null, destroyed: false };
    const factory = canvasGuest({ async setup() { return {}; }, frame() {}, onProps(s, p) { seen.props = p; }, destroy() { seen.destroyed = true; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
    guest.onProps({ x: 9 });
    guest.destroy();
    assert.deepEqual(seen.props, { x: 9 });
    assert.equal(seen.destroyed, true);
  });

  test("a throw in a later hook is caught (console.warn), not propagated", async () => {
    const warns = [];
    const orig = console.warn; console.warn = (...a) => warns.push(a);
    try {
      const factory = canvasGuest({ async setup() { return {}; }, frame() {}, onProps() { throw new Error("boom"); } });
      const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
      guest.onProps({}); // must NOT throw
      assert.equal(warns.length, 1);
      assert.match(String(warns[0][0]), /onProps threw/);
    } finally { console.warn = orig; }
  });
});
