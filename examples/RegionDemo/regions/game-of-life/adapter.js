// Hosts our AssemblyScript Game-of-Life guest (./universe.ts -> ./universe.wasm):
// a DOM-free wasm module that computes the board in linear memory, so it runs
// inside the region's Web Worker. This adapter instantiates it, ticks it, blits
// the bit-packed cells onto the OffscreenCanvas, and REFLOWS the board (re-seeds
// at a new cell grid) whenever the region resizes — cells stay a constant size.

// Pure, injected core — unit-tested against a fake `ex` (no real wasm).
export function makeGuest({ ex, canvas, ctx2d, cell, speed = 1, emit }) {
  let gen = 0;
  let rate = speed;
  let W = 0; // board cols
  let H = 0; // board rows
  let px = cell; // device px per cell (cell * dpr)

  // Reflow to fill a device-pixel region: keep cells ~`cell` CSS px, so the grid
  // re-tessellates (more/fewer cells) on resize instead of scaling. Re-seeds.
  function resize(devW, devH, dpr) {
    const cols = Math.max(8, Math.floor(devW / dpr / cell));
    const rows = Math.max(8, Math.floor(devH / dpr / cell));
    if (cols === W && rows === H) return;
    W = cols;
    H = rows;
    px = Math.max(1, Math.round(cell * dpr));
    ex.init(W, H);
    canvas.width = W * px;
    canvas.height = H * px;
  }

  function draw() {
    const cells = new Uint8Array(ex.memory.buffer, ex.cells() >>> 0, Math.ceil((W * H) / 8));
    ctx2d.fillStyle = "#fff";
    ctx2d.fillRect(0, 0, W * px, H * px);
    ctx2d.fillStyle = "#111";
    for (let i = 0; i < W * H; i++) {
      if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % W) * px, ((i / W) | 0) * px, px, px);
    }
    // Debug: gray border marking the guest's actual canvas bounds.
    ctx2d.strokeStyle = "#888";
    ctx2d.lineWidth = 2;
    ctx2d.strokeRect(1, 1, W * px - 2, H * px - 2);
  }

  return {
    onProps(p) { if (p && p.speed != null) rate = p.speed; },
    onResize(devW, devH, dpr) { resize(devW, devH, dpr); },
    frame() {
      if (!W) return; // not sized yet
      for (let i = 0; i < rate; i++) { ex.tick(); gen++; }
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
  guest.onResize(size.w, size.h, size.dpr); // initial sizing
  return guest;
}
