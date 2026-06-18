import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { makeGuest } from "../../../examples/RegionDemo/regions/game-of-life/adapter.js";

// A fake wasm `ex`: bit-packed cells in a buffer + init/cells/tick/memory.
// init() is a no-op so the preset live cells survive (the test controls them);
// the real wasm re-seeds on init — that's covered by universe-wasm.test.js.
// Grids stay >= 8 because makeGuest clamps the board to a minimum of 8x8.
function fakeEx(w, h, aliveIndices) {
  const bytes = new Uint8Array(Math.ceil((w * h) / 8));
  for (const i of aliveIndices) bytes[i >> 3] |= (1 << (i & 7));
  let gen = 0;
  return {
    memory: { buffer: bytes.buffer },
    init: () => {},
    cells: () => 0,
    tick: () => { gen++; },
    _gen: () => gen,
  };
}

function fakeCtx() {
  const rects = [];
  const strokes = [];
  return {
    fillStyle: "", strokeStyle: "", lineWidth: 0,
    fillRect: (x, y, w, h) => rects.push([x, y, w, h]),
    strokeRect: (x, y, w, h) => strokes.push([x, y, w, h]),
    _rects: rects, _strokes: strokes,
  };
}

describe("game-of-life adapter core", () => {
  test("draws a fillRect per live cell at the right grid coords", () => {
    // 10x8 grid; live cells at index 0 -> (0,0) and index 23 -> (3,2).
    const ex = fakeEx(10, 8, [0, 23]);
    const ctx2d = fakeCtx();
    const guest = makeGuest({ ex, canvas: {}, ctx2d, cell: 10, emit: () => {} });
    guest.onResize(100, 80, 1); // -> 10x8 grid, 10px cells
    guest.frame();
    assert.deepEqual(ctx2d._rects.filter((r) => r[2] === 10 && r[3] === 10),
      [[0, 0, 10, 10], [30, 20, 10, 10]]);
  });

  test("ticks `speed` times per frame and emits a generation event periodically", () => {
    const ex = fakeEx(8, 8, []);
    let emitted = null;
    const guest = makeGuest({ ex, canvas: {}, ctx2d: fakeCtx(), cell: 4, speed: 64, emit: (e) => { emitted = e; } });
    guest.onResize(32, 32, 1); // -> 8x8 grid
    guest.frame();
    assert.equal(ex._gen(), 64);
    assert.deepEqual(emitted, { kind: "generation", value: 64 });
  });

  test("onResize reflows: re-inits to the new cell grid, skipping no-op resizes", () => {
    const initCalls = [];
    const ex = fakeEx(8, 8, []);
    ex.init = (w, h) => initCalls.push([w, h]);
    const canvas = {};
    const guest = makeGuest({ ex, canvas, ctx2d: fakeCtx(), cell: 10, emit: () => {} });
    guest.onResize(150, 100, 1);  // 15x10
    guest.onResize(300, 200, 2);  // dpr 2 -> 15x10 again, no re-init
    guest.onResize(250, 150, 1);  // 25x15 -> re-init
    assert.deepEqual(initCalls, [[15, 10], [25, 15]]);
    assert.equal(canvas.width, 25 * 10); // device-px buffer for the last grid
  });
});
