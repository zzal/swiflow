// Behaviour test for the COMPILED AssemblyScript Game-of-Life guest
// (examples/RegionDemo/regions/game-of-life/universe.wasm). Loads the real wasm
// and checks Game-of-Life semantics + the bit-packed memory layout the host
// adapter reads. Regenerate the wasm with `npm run build:gol` after editing
// universe.ts; this test guards against gross drift between source and artifact.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const wasmUrl = new URL(
  "../../../examples/RegionDemo/regions/game-of-life/universe.wasm",
  import.meta.url,
);
const bytes = await readFile(fileURLToPath(wasmUrl));
const { instance } = await WebAssembly.instantiate(bytes, {
  env: { abort: () => { throw new Error("AssemblyScript abort()"); } },
});
const ex = instance.exports;

test("a blinker oscillates between horizontal and vertical (period 2)", () => {
  ex.initEmpty(5, 5);
  ex.set(1, 2); ex.set(2, 2); ex.set(3, 2); // horizontal bar
  ex.tick();
  // becomes a vertical bar at column 2
  assert.equal(ex.get(2, 1), 1, "top appears");
  assert.equal(ex.get(2, 2), 1, "centre survives");
  assert.equal(ex.get(2, 3), 1, "bottom appears");
  assert.equal(ex.get(1, 2), 0, "left dies");
  assert.equal(ex.get(3, 2), 0, "right dies");
  ex.tick();
  // and back to horizontal
  assert.equal(ex.get(1, 2), 1);
  assert.equal(ex.get(2, 2), 1);
  assert.equal(ex.get(3, 2), 1);
  assert.equal(ex.get(2, 1), 0);
  assert.equal(ex.get(2, 3), 0);
});

test("cells() exposes bit-packed state at a readable memory pointer", () => {
  ex.initEmpty(16, 1);
  ex.set(0, 0); ex.set(9, 0);
  const ptr = ex.cells() >>> 0;
  const view = new Uint8Array(ex.memory.buffer, ptr, 2);
  assert.equal(view[0] & 1, 1, "cell 0 -> byte 0 bit 0");
  assert.equal((view[1] >> 1) & 1, 1, "cell 9 -> byte 1 bit 1");
});

test("init seeds a lively but non-saturated board", () => {
  ex.init(32, 32);
  const view = new Uint8Array(ex.memory.buffer, ex.cells() >>> 0, (32 * 32) / 8);
  let live = 0;
  for (let i = 0; i < 32 * 32; i++) if ((view[i >> 3] >> (i & 7)) & 1) live++;
  assert.ok(live > 0 && live < 32 * 32, `seeded ${live} live cells`);
});
