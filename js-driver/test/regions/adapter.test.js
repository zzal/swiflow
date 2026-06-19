import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { hooks, drawCells } from "../../../examples/RegionDemo/regions/game-of-life/adapter.js";

// Oversized buffer so drawCells never reads out of bounds at any grid.
function fakeEx(aliveIndices) {
  const bytes = new Uint8Array(8192);
  for (const i of aliveIndices) bytes[i >> 3] |= (1 << (i & 7));
  let gen = 0; const inits = [];
  return {
    memory: { buffer: bytes.buffer },
    init: (w, h, seed) => inits.push([w, h, seed]),
    cells: () => 0, tick: () => { gen++; }, _gen: () => gen, _inits: inits,
  };
}
function fakeCtx() {
  const rects = [];
  return {
    fillStyle: "", font: "", textBaseline: "",
    fillRect: (x, y, w, h) => rects.push([x, y, w, h]),
    measureText: (s) => ({ width: s.length * 6 }), fillText() {},
    _rects: rects,
  };
}

describe("game-of-life hooks", () => {
  test("drawCells draws a fillRect per live cell at grid coords", () => {
    const ex = fakeEx([0, 23]); // 10x8 grid: 0 -> (0,0), 23 -> (3,2)
    const ctx2d = fakeCtx();
    drawCells(ctx2d, ex, 10, 8, 10);
    assert.deepEqual(ctx2d._rects.filter((r) => r[2] === 10 && r[3] === 10),
      [[0, 0, 10, 10], [30, 20, 10, 10]]);
  });

  test("resize re-seeds with the current seed and resets the count", () => {
    const ex = fakeEx([]);
    const s = { ex, seed: 7, gen: 99, reseed: false };
    hooks.resize(s, { cols: 12, rows: 9 });
    assert.deepEqual(ex._inits, [[12, 9, 7]]);
    assert.equal(s.gen, 0);
  });

  test("onProps flags a reseed only on a reset-token change", () => {
    const s = { seed: 0, reseed: false };
    hooks.onProps(s, { reset: 0 }); assert.equal(s.reseed, false);
    hooks.onProps(s, { reset: 1 }); assert.equal(s.reseed, true); assert.equal(s.seed, 1);
  });

  test("frame ticks, applies a pending reseed once, emits generation every 64", () => {
    const ex = fakeEx([]);
    const emits = [];
    const s = { ex, seed: 2, gen: 0, reseed: true };
    const ctx = { ctx2d: fakeCtx(), cols: 8, rows: 8, cell: 6, dpr: 1, fps: 60, emit: (e) => emits.push(e) };
    for (let i = 0; i < 64; i++) hooks.frame(s, ctx);
    assert.deepEqual(ex._inits, [[8, 8, 2]]); // reseed applied once, on the first frame
    assert.equal(s.gen, 64);
    assert.deepEqual(emits.at(-1), { kind: "generation", value: 64 });
  });
});
