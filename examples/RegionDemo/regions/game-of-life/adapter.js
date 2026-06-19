// Hosts our AssemblyScript Game-of-Life guest (./universe.ts -> ./universe.wasm):
// a DOM-free wasm module that computes the board in linear memory, so it runs
// inside the region's Web Worker. This adapter instantiates it, ticks it, blits
// the bit-packed cells onto the OffscreenCanvas, and re-seeds the board (a fresh
// generation 0) when the region resizes or a reset signal arrives via props.

// Pure, injected core — unit-tested against a fake `ex` (no real wasm).
export function makeGuest({ ex, canvas, ctx2d, cell, speed = 1, emit }) {
  let gen = 0;
  let rate = speed;
  let W = 0; // board cols
  let H = 0; // board rows
  let px = cell; // device px per cell (cell * dpr)
  let seed = 0; // reset token doubles as the board seed (each reset -> new board)
  let fps = 0; // smoothed frames/second, overlaid on the canvas

  function draw() {
    const cells = new Uint8Array(ex.memory.buffer, ex.cells() >>> 0, Math.ceil((W * H) / 8));
    ctx2d.fillStyle = "#fff";
    ctx2d.fillRect(0, 0, W * px, H * px);
    ctx2d.fillStyle = "#111";
    for (let i = 0; i < W * H; i++) {
      if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % W) * px, ((i / W) | 0) * px, px, px);
    }
    // FPS overlay, top-left: dark pill + white text (~13 CSS px, dpr-scaled).
    const label = `${Math.round(fps)} fps`;
    const fontPx = Math.round(13 * (px / cell));
    ctx2d.font = `${fontPx}px system-ui, sans-serif`;
    ctx2d.textBaseline = "top";
    const padX = Math.round(fontPx * 0.5);
    const padY = Math.round(fontPx * 0.35);
    const tw = ctx2d.measureText(label).width;
    ctx2d.fillStyle = "rgba(17,17,17,0.7)";
    ctx2d.fillRect(0, 0, tw + padX * 2, fontPx + padY * 2);
    ctx2d.fillStyle = "#fff";
    ctx2d.fillText(label, padX, padY);
  }

  // Fresh board on the current grid + a fresh generation count (emit 0 so the
  // host's counter resets too).
  function reseed() {
    ex.init(W, H, seed);
    gen = 0;
    emit({ kind: "generation", value: 0 });
    draw();
  }

  // Reflow to fill a device-pixel region: keep cells ~`cell` CSS px so the grid
  // re-tessellates (more/fewer cells) instead of scaling, then re-seed.
  function resize(devW, devH, dpr) {
    const cols = Math.max(8, Math.floor(devW / dpr / cell));
    const rows = Math.max(8, Math.floor(devH / dpr / cell));
    const ppx = Math.max(1, Math.round(cell * dpr));
    if (cols === W && rows === H && ppx === px) return;
    const gridChanged = cols !== W || rows !== H;
    W = cols;
    H = rows;
    px = ppx;
    canvas.width = W * px;
    canvas.height = H * px;
    // New grid -> fresh board (+ reset count). Same grid at a new device
    // resolution (dpr change) -> keep the board, just redraw at the new size.
    if (gridChanged) reseed();
    else draw();
  }

  return {
    onProps(p) {
      if (!p) return;
      if (p.speed != null) rate = p.speed;
      // A changed reset token re-seeds with a fresh board (and resets the count).
      if (p.reset != null && p.reset !== seed && W) { seed = p.reset; reseed(); }
    },
    onResize(devW, devH, dpr) { resize(devW, devH, dpr); },
    frame(dt) {
      if (!W) return; // not sized yet
      for (let i = 0; i < rate; i++) { ex.tick(); gen++; }
      // Exponential moving average of the per-frame rate (dt is ms since last frame).
      if (dt > 0) fps = fps ? fps * 0.9 + (1000 / dt) * 0.1 : 1000 / dt;
      draw();
      if (gen % 64 === 0) emit({ kind: "generation", value: gen });
    },
    destroy() {},
  };
}

// The guest factory the worker calls: instantiate the wasm, wire it to makeGuest,
// and size to the region. onResize drives both the initial sizing and every later
// resize. (Exercised by the browser e2e; makeGuest + universe.wasm are unit-tested.)
export default async function gameOfLife(canvas, props, ctx) {
  const res = await fetch(new URL("./universe.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {
    env: { abort: () => { throw new Error("AssemblyScript abort()"); } },
  });
  const cell = (props && props.cellSize) || 6;
  const guest = makeGuest({
    ex: instance.exports, canvas, ctx2d: canvas.getContext("2d"),
    cell, speed: (props && props.speed) || 1, emit: ctx.emit,
  });
  const size = (ctx && ctx.size) || { w: 360, h: 360, dpr: 1 };
  guest.onResize(size.w, size.h, size.dpr); // initial sizing + seed
  return guest;
}
