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

  test("props and destroy reach the hooks", async () => {
    const seen = { props: null, destroyed: false };
    const factory = canvasGuest({ async setup() { return {}; }, frame() {}, props(s, p) { seen.props = p; }, destroy() { seen.destroyed = true; } });
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
      const factory = canvasGuest({ async setup() { return {}; }, frame() {}, props() { throw new Error("boom"); } });
      const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
      guest.onProps({}); // must NOT throw
      assert.equal(warns.length, 1);
      assert.match(String(warns[0][0]), /props threw/);
    } finally { console.warn = orig; }
  });

  test("emit is delivered on the frame context only — not setup or resize", async () => {
    let setupArg = null, resizeCtx = null, frameCtx = null;
    const factory = canvasGuest({
      async setup(arg) { setupArg = arg; return {}; },
      resize(s, c) { resizeCtx = c; },
      frame(s, c) { frameCtx = c; },
    });
    const guest = await factory(fakeCanvas(), { a: 1 }, fakeHost({ w: 100, h: 80, dpr: 1 }));
    guest.frame(16);
    assert.equal(setupArg.emit, undefined);          // setup gets { props } only
    assert.equal(resizeCtx.emit, undefined);         // the layout context carries no emit
    assert.equal(typeof frameCtx.emit, "function");  // frame is emit's single home
  });
});

describe("canvasGuest — grid mode", () => {
  function fakeCanvas() { const ctx2d = { _is: "ctx2d" }; return { width: 0, height: 0, getContext: () => ctx2d, _ctx: ctx2d }; }
  function fakeHost(size) { return { emit: () => {}, size }; }

  test("derives cols/rows/cell from cellSize, sizes the buffer, clamps to 8", async () => {
    const got = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { got.push([c.cols, c.rows, c.cell]); }, frame() {} });
    const canvas = fakeCanvas();
    await factory(canvas, null, fakeHost({ w: 200, h: 50, dpr: 1 })); // cols=20, rows=max(8,5)=8
    assert.deepEqual(got, [[20, 8, 10]]);
    assert.equal(canvas.width, 200);  // 20 * 10
    assert.equal(canvas.height, 80);  // 8 * 10
  });

  test("a pure-dpr change keeps the grid: resize skipped, buffer still re-sized", async () => {
    const grids = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { grids.push([c.cols, c.rows, c.cell]); }, frame() {} });
    const canvas = fakeCanvas();
    const guest = await factory(canvas, null, fakeHost({ w: 200, h: 100, dpr: 1 })); // 20x10, cell 10, buffer 200x100
    guest.onResize(400, 200, 2); // same CSS size at dpr 2 → cols 20, rows 10 (unchanged), cell 20
    assert.deepEqual(grids, [[20, 10, 10]]); // only the initial resize
    assert.equal(canvas.width, 400);   // buffer re-sized: 20 * 20
    assert.equal(canvas.height, 200);  // 10 * 20
  });

  test("resize fires when the grid count changes", async () => {
    const grids = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { grids.push([c.cols, c.rows]); }, frame() {} });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 200, h: 100, dpr: 1 })); // 20x10
    guest.onResize(300, 100, 1); // 30x10 → change
    assert.deepEqual(grids, [[20, 10], [30, 10]]);
  });

  test("frame forwards cols/rows/cell/dpr", async () => {
    let f = null;
    const factory = canvasGuest({ cellSize: 6, async setup() { return {}; }, frame(s, c) { f = c; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 120, h: 60, dpr: 1 })); // 20x10, cell 6
    guest.frame(16);
    assert.equal(f.cols, 20); assert.equal(f.rows, 10); assert.equal(f.cell, 6); assert.equal(f.dpr, 1);
    assert.ok(f.ctx2d && f.dt === 16);
  });
});

