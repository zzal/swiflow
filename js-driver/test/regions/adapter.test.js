import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { makeGuest } from "../../../examples/RegionDemo/regions/game-of-life/adapter.js";

function fakeUniverse(w, h, aliveIndices) {
  const bytes = new Uint8Array(Math.ceil((w * h) / 8));
  for (const i of aliveIndices) bytes[i >> 3] |= (1 << (i & 7));
  let gen = 0;
  return {
    memory: { buffer: bytes.buffer },
    universe: {
      width: () => w, height: () => h, cells: () => 0,
      tick: () => { gen++; }, free: () => {},
      _gen: () => gen,
    },
  };
}

function fakeCtx() {
  const rects = [];
  return { fillStyle: "", fillRect: (x, y, w, h) => rects.push([x, y, w, h]), _rects: rects };
}

describe("game-of-life adapter core", () => {
  test("draws a fillRect per live cell at the right grid coords", () => {
    const { memory, universe } = fakeUniverse(3, 2, [0, 5]);
    const ctx2d = fakeCtx();
    const guest = makeGuest({
      wasmMemory: memory, universe, ctx2d,
      width: 3, height: 2, cell: 10, emit: () => {},
    });
    guest.frame();
    assert.deepEqual(ctx2d._rects.filter((r) => r[2] === 10 && r[3] === 10),
      [[0, 0, 10, 10], [20, 10, 10, 10]]);
  });

  test("ticks `speed` times per frame and emits a generation event periodically", () => {
    const { memory, universe } = fakeUniverse(2, 2, []);
    let emitted = null;
    const guest = makeGuest({
      wasmMemory: memory, universe, ctx2d: fakeCtx(),
      width: 2, height: 2, cell: 4, speed: 64, emit: (e) => { emitted = e; },
    });
    guest.frame();
    assert.equal(universe._gen(), 64);
    assert.deepEqual(emitted, { kind: "generation", value: 64 });
  });
});
