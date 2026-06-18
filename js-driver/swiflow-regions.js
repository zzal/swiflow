// js-driver/swiflow-regions.js
//
// Swiflow Regions browser runtime. Load via <script type="module">. Defines the
// <sf-region> custom element (main thread) and the worker-side guest host. All
// three building blocks are exported for unit testing; the element self-registers
// only in a window context (a later task wires the real worker).

const PROTOCOL = 1;

// Worker-side: translate the protocol to/from a guest ES module instance.
// `deps.post(msg)` sends an envelope; `deps.importGuest(source)` resolves the
// guest factory (real impl uses dynamic import()); `deps.raf` schedules a frame.
export function createGuestHost({ post, importGuest, raf }) {
  const requestFrame = raf || ((cb) => (typeof requestAnimationFrame === "function" ? requestAnimationFrame(cb) : null));
  let guest = null;
  let loopId = null;
  let lastTs = 0;

  function emit(event) {
    post({ v: PROTOCOL, kind: "event", payload: JSON.stringify(event) });
  }

  function startLoop() {
    if (loopId !== null || !guest?.frame) return;
    lastTs = 0;
    const tick = (ts) => {
      if (!guest?.frame) { loopId = null; return; }
      const dt = lastTs ? ts - lastTs : 0;
      lastTs = ts;
      try { guest.frame(dt); } catch (e) { post({ v: PROTOCOL, kind: "error", payload: { code: "frame-failed", message: String(e) } }); }
      loopId = requestFrame(tick);
    };
    loopId = requestFrame(tick);
  }
  function stopLoop() { loopId = null; lastTs = 0; }

  async function handle(msg, canvas) {
    const { kind, payload } = msg;
    switch (kind) {
      case "init": {
        try {
          const factory = await importGuest(payload.source);
          const props = payload.props ? JSON.parse(payload.props) : null;
          guest = await factory(canvas, props, { emit, size: payload.size });
          post({ v: PROTOCOL, kind: "ready", payload: { protocol: PROTOCOL } });
          startLoop();
        } catch (e) {
          post({ v: PROTOCOL, kind: "error", payload: { code: "init-failed", message: String(e) } });
        }
        return;
      }
      case "props":  guest?.onProps?.(JSON.parse(payload)); return;
      case "resize": guest?.onResize?.(payload.w, payload.h, payload.dpr); return;
      case "pause":  stopLoop(); return;
      case "resume": startLoop(); return;
      case "destroy":
        stopLoop();
        try { guest?.destroy?.(); } catch { /* ignore */ }
        guest = null;
        return;
    }
  }

  return { handle, emit };
}
