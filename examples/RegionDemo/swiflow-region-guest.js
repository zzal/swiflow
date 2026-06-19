// js-driver/swiflow-region-guest.js
//
// canvasGuest: a guest-SDK shim for Swiflow Regions. Turn a small config of hooks
// into a conforming guest factory — the shim owns the OffscreenCanvas 2D context,
// dpr-crisp sizing, resize→grid reflow detection, the fps EMA, and lifecycle, so
// the author writes only setup() + a per-frame draw. The raw
// (canvas, props, ctx) => guest contract stays available for advanced guests.
//
// `cellSize` present → grid mode: the shim derives cols/rows from the measured
// size, snaps the canvas to whole cells, and fires `resize` only when the cell
// count changes. Absent → raster mode: the canvas is the measured device size and
// `resize` fires on any device-dim change.

export function canvasGuest(config) {
  const { cellSize, setup, resize, frame, onProps, destroy } = config;
  const grid = cellSize != null;

  function guard(label, fn) {
    try { return fn(); } catch (e) { console.warn(`[region-guest] ${label} threw:`, e); }
  }

  return async function guestFactory(canvas, props, host) {
    const ctx2d = canvas.getContext("2d");
    const emit = host.emit;
    const state = await setup({ props, emit });

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
    function dims() {
      return grid ? { cols, rows, cell, dpr, emit } : { width, height, dpr, emit };
    }

    // Initial sizing runs inside the factory, so a throw here → host init-failed.
    const s0 = host.size || { w: 360, h: 360, dpr: 1 };
    applySize(s0.w, s0.h, s0.dpr);
    if (resize) resize(state, dims());

    return {
      onResize(w, h, d) {
        if (applySize(w, h, d) && resize) guard("resize", () => resize(state, dims()));
      },
      onProps(p) { if (onProps) guard("onProps", () => onProps(state, p)); },
      frame(dt) {
        if (dt > 0) fps = fps ? fps * 0.9 + (1000 / dt) * 0.1 : 1000 / dt;
        const base = { ctx2d, dt, fps, dpr, emit };
        frame(state, grid ? { ...base, cols, rows, cell } : { ...base, width, height });
      },
      destroy() { if (destroy) guard("destroy", () => destroy(state)); },
    };
  };
}
