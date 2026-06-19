// Hosts our AssemblyScript Game-of-Life guest (./universe.ts -> ./universe.wasm)
// via the canvasGuest SDK: the shim owns the canvas, dpr-crisp grid sizing, reflow,
// fps, and lifecycle; here we write only the load + the per-frame tick/draw.
import { canvasGuest } from "../../swiflow-region-guest.js";

async function loadUniverse() {
  const res = await fetch(new URL("./universe.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(),
    { env: { abort: () => { throw new Error("AssemblyScript abort()"); } } });
  return instance.exports;
}

// Pure draw helpers (the only thing the shim can't own). Exported for unit tests.
export function drawCells(ctx2d, ex, cols, rows, cell) {
  const cells = new Uint8Array(ex.memory.buffer, ex.cells() >>> 0, Math.ceil((cols * rows) / 8));
  ctx2d.fillStyle = "#fff";
  ctx2d.fillRect(0, 0, cols * cell, rows * cell);
  ctx2d.fillStyle = "#111";
  for (let i = 0; i < cols * rows; i++) {
    if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % cols) * cell, ((i / cols) | 0) * cell, cell, cell);
  }
}

export function drawFps(ctx2d, fps, dpr) {
  const label = `${Math.round(fps)} fps`;
  const fontPx = Math.round(13 * dpr);
  ctx2d.font = `${fontPx}px system-ui, sans-serif`;
  ctx2d.textBaseline = "top";
  const padX = Math.round(fontPx * 0.5), padY = Math.round(fontPx * 0.35);
  const tw = ctx2d.measureText(label).width;
  ctx2d.fillStyle = "rgba(17,17,17,0.7)";
  ctx2d.fillRect(0, 0, tw + padX * 2, fontPx + padY * 2);
  ctx2d.fillStyle = "#fff";
  ctx2d.fillText(label, padX, padY);
}

// The guest hooks. Exported so the GoL logic is unit-tested directly.
export const hooks = {
  cellSize: 6,
  async setup() { return { ex: await loadUniverse(), seed: 0, gen: 0, reseed: false }; },
  resize(s, { cols, rows }) { s.ex.init(cols, rows, s.seed); s.gen = 0; },
  onProps(s, p) { if (p && p.reset !== s.seed) { s.seed = p.reset; s.reseed = true; } },
  frame(s, { ctx2d, cols, rows, cell, dpr, fps, emit }) {
    if (s.reseed) { s.ex.init(cols, rows, s.seed); s.gen = 0; s.reseed = false; }
    s.ex.tick(); s.gen++;
    drawCells(ctx2d, s.ex, cols, rows, cell);
    drawFps(ctx2d, fps, dpr);
    if (s.gen % 64 === 0) emit({ kind: "generation", value: s.gen });
  },
};

export default canvasGuest(hooks);
