// Hosts our AssemblyScript Game-of-Life guest (./universe.ts -> ./universe.wasm):
// a DOM-free wasm module that computes the board in linear memory, so it runs
// inside the region's Web Worker. This adapter instantiates it, ticks it, and
// blits the bit-packed cells onto the OffscreenCanvas.

// Pure, injected core — unit-tested without the real wasm.
export function makeGuest({ wasmMemory, universe, ctx2d, width, height, cell, speed = 1, emit }) {
  let gen = 0;
  let rate = speed;
  function draw() {
    const cells = new Uint8Array(wasmMemory.buffer, universe.cells(), Math.ceil((width * height) / 8));
    ctx2d.fillStyle = "#fff";
    ctx2d.fillRect(0, 0, width * cell, height * cell);
    ctx2d.fillStyle = "#111";
    for (let i = 0; i < width * height; i++) {
      if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % width) * cell, ((i / width) | 0) * cell, cell, cell);
    }
  }
  return {
    onProps(p) { if (p && p.speed != null) rate = p.speed; },
    frame() {
      for (let i = 0; i < rate; i++) { universe.tick(); gen++; }
      draw();
      if (gen % 64 === 0) emit({ kind: "generation", value: gen });
    },
    destroy() { universe.free?.(); },
  };
}

// The guest factory the worker calls: instantiate the wasm, size the board to fill
// the region frame, and wire it to makeGuest. (Exercised by the browser e2e; the
// wasm fetch can't run in node, but makeGuest + universe.wasm are unit-tested.)
export default async function gameOfLife(canvas, props, ctx) {
  const res = await fetch(new URL("./universe.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {
    env: { abort: () => { throw new Error("AssemblyScript abort()"); } },
  });
  const ex = instance.exports;

  const cell = (props && props.cellSize) || 6;
  const size = (ctx && ctx.size) || { w: 360, h: 360, dpr: 1 };
  const dpr = size.dpr || 1;
  const cols = Math.max(8, Math.floor(size.w / dpr / cell));
  const rows = Math.max(8, Math.floor(size.h / dpr / cell));
  ex.init(cols, rows);
  canvas.width = cols * cell;
  canvas.height = rows * cell;

  const universe = {
    width: () => ex.width(),
    height: () => ex.height(),
    cells: () => ex.cells() >>> 0,
    tick: () => ex.tick(),
    free: () => {},
  };
  return makeGuest({
    wasmMemory: ex.memory, universe, ctx2d: canvas.getContext("2d"),
    width: cols, height: rows, cell, speed: (props && props.speed) || 1, emit: ctx.emit,
  });
}
