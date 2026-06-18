// Hosts the EXTERNAL rustwasm/wasm_game_of_life module unmodified: its `Universe`
// is DOM-free pure compute, so it runs in our Web Worker. This adapter ticks it
// and blits the cell bitmap to the OffscreenCanvas. Provenance of the vendored
// wasm: see ./PROVENANCE.md.

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

// The guest factory the worker calls. Imports the EXTERNAL wasm module and wires
// it to makeGuest. (Exercised by the browser e2e; the wasm import can't run in node.)
export default async function gameOfLife(canvas, props, ctx) {
  const mod = await import("./wasm_game_of_life.js");
  const wasm = await mod.default();
  const universe = mod.Universe.new();
  const width = universe.width(), height = universe.height();
  const cell = (props && props.cellSize) || 6;
  canvas.width = width * cell;
  canvas.height = height * cell;
  return makeGuest({
    wasmMemory: wasm.memory, universe, ctx2d: canvas.getContext("2d"),
    width, height, cell, speed: (props && props.speed) || 1, emit: ctx.emit,
  });
}
