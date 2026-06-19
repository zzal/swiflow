// js-driver/swiflow-region-guest.js
//
// canvasGuest: a guest-SDK shim for Swiflow Regions. Turn a small config of hooks
// into a conforming guest factory — the shim owns the OffscreenCanvas 2D context,
// dpr-crisp sizing, resize→grid reflow detection, the fps EMA, and lifecycle, so
// the author writes only setup() + a per-frame draw. The raw
// (canvas, props, ctx) => guest contract stays available for advanced guests.

export function canvasGuest(config) {
  const { setup, resize, frame, onProps, destroy } = config;

  // Catch a throw in a post-setup hook so a guest bug doesn't escape uncaught into
  // the worker message handler. setup/frame keep the host's init/frame envelopes.
  function guard(label, fn) {
    try { return fn(); } catch (e) { console.warn(`[region-guest] ${label} threw:`, e); }
  }

  return async function guestFactory(canvas, props, host) {
    const ctx2d = canvas.getContext("2d");
    const emit = host.emit;
    const state = await setup({ props, emit });

    let width = 0, height = 0, dpr = 1, fps = 0;

    // Size the canvas buffer to a measured device size. Returns whether the
    // raster device dims changed (so resize fires only on a real change).
    function applySize(devW, devH, devDpr) {
      dpr = devDpr || 1;
      const changed = devW !== width || devH !== height;
      width = devW; height = devH;
      if (canvas.width !== devW) canvas.width = devW;
      if (canvas.height !== devH) canvas.height = devH;
      return changed;
    }
    function dims() { return { width, height, dpr, emit }; }

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
        frame(state, { ctx2d, width, height, dpr, dt, fps, emit });
      },
      destroy() { if (destroy) guard("destroy", () => destroy(state)); },
    };
  };
}
