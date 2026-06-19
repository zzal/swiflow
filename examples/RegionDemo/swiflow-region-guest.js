// js-driver/swiflow-region-guest.js
//
// canvasGuest: a guest-SDK shim for Swiflow Regions. Turn a small config of hooks
// into a conforming guest factory — the shim owns the OffscreenCanvas 2D context,
// dpr-crisp sizing, resize→reflow detection, the fps EMA, and lifecycle, so the
// author writes only setup() + a per-frame draw. The raw
// (canvas, props, ctx) => guest contract stays available for advanced guests.
//
// Two layout modes, chosen by whether the config names a `cellSize`:
//
//   • RASTER mode (no `cellSize`) — the canvas buffer is the measured device
//     size; the layout context carries { width, height, dpr }; `resize` fires on
//     any device-dim change.
//   • GRID mode (`cellSize` set) — the shim derives whole cols/rows from the
//     measured size and snaps the buffer to whole cells; the layout context
//     carries { cols, rows, cell, dpr }; `resize` fires only when the cell count
//     changes.
//
// (A future typed build can model this as a discriminated GridConfig | RasterConfig.)
//
// Config hooks — `setup` and `frame` are required, the rest optional:
//   setup({ props }) → state   run once before the first paint; the returned
//                              object is the mutable state threaded into every hook
//   resize(state, layout)      layout changed — `layout` is the mode's context
//   frame(state, frameCtx)     per animation frame; frameCtx = layout +
//                              { ctx2d, dt, fps, emit } — `emit` lives here only
//   props(state, next)         the host pushed new props
//   destroy(state)             teardown

export function canvasGuest(config) {
  const { cellSize, setup, resize, frame, props, destroy } = config;
  const grid = cellSize != null;

  function guard(label, fn) {
    try { return fn(); } catch (e) { console.warn(`[region-guest] ${label} threw:`, e); }
  }

  return async function guestFactory(canvas, initialProps, host) {
    const ctx2d = canvas.getContext("2d");
    const emit = host.emit;
    const state = await setup({ props: initialProps });

    let cols = 0, rows = 0, cell = grid ? cellSize : 0;
    let width = 0, height = 0, dpr = 1, fps = 0;

    // Size the canvas buffer to a measured device size. Returns whether the
    // logical layout changed (grid cols/rows, or raster device dims).
    function applySize(devW, devH, devDpr) {
      dpr = devDpr || 1;
      let bw, bh, changed;
      if (grid) {
        const c = Math.max(8, Math.floor(devW / dpr / cellSize));
        const r = Math.max(8, Math.floor(devH / dpr / cellSize));
        cell = Math.max(1, Math.round(cellSize * dpr));
        changed = c !== cols || r !== rows;
        cols = c; rows = r; bw = c * cell; bh = r * cell;
      } else {
        changed = devW !== width || devH !== height;
        width = devW; height = devH; bw = devW; bh = devH;
      }
      if (canvas.width !== bw) canvas.width = bw;
      if (canvas.height !== bh) canvas.height = bh;
      return changed;
    }
    // The layout context handed to `resize`; `frame` builds the same shape plus
    // { ctx2d, dt, fps, emit }.
    function dims() {
      return grid ? { cols, rows, cell, dpr } : { width, height, dpr };
    }

    // Initial sizing runs inside the factory, so a throw here → host init-failed.
    const s0 = host.size || { w: 360, h: 360, dpr: 1 };
    applySize(s0.w, s0.h, s0.dpr);
    if (resize) resize(state, dims());

    return {
      onResize(w, h, d) {
        if (applySize(w, h, d) && resize) guard("resize", () => resize(state, dims()));
      },
      onProps(p) { if (props) guard("props", () => props(state, p)); },
      frame(dt) {
        if (dt > 0) fps = fps ? fps * 0.9 + (1000 / dt) * 0.1 : 1000 / dt;
        const base = { ctx2d, dt, fps, dpr, emit };
        frame(state, grid ? { ...base, cols, rows, cell } : { ...base, width, height });
      },
      destroy() { if (destroy) guard("destroy", () => destroy(state)); },
    };
  };
}
