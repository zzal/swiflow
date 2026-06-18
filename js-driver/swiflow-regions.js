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

// --- Main-thread: the <sf-region> custom element ---
//
// Seams (defaulted to real browser APIs by a later task, overridden in tests):
//   makeWorker()           -> a Worker-like { postMessage, terminate, onmessage }
//   makeCanvas()           -> a <canvas> (or fake) exposing transferControlToOffscreen()
//   schedule(cb)           -> coalesce work to a frame
//   observeSize(el, cb)    -> { disconnect() }; calls cb(w, h, dpr) on resize
//   observeVisible(el, cb) -> { disconnect() }; calls cb(isVisible)

export class SfRegion {
  static elementClass(win, seams) {
    return class SfRegionElement extends win.HTMLElement {
      connectedCallback() {
        if (this._worker) return; // idempotent / reconnection no-op
        this._seams = seams;
        this._propsLatest = this.sfProps ?? null;
        this._propsDirty = false;

        const canvas = seams.makeCanvas(this);
        if (canvas.style) { canvas.style.width = "100%"; canvas.style.height = "100%"; }
        if (canvas.nodeType) this.appendChild(canvas);
        const offscreen = canvas.transferControlToOffscreen();

        const size = this._measure();
        this._worker = seams.makeWorker(this);
        this._worker.onmessage = (e) => this._onWorkerMessage(e.data);
        this._post(
          { v: 1, kind: "init", canvas: offscreen, payload: { protocol: 1, source: this.getAttribute("data-source"), props: this._propsLatest, size } },
          [offscreen]
        );

        this._sizeObs = seams.observeSize(this, (w, h, dpr) => this._post({ v: 1, kind: "resize", payload: { w, h, dpr } }));
        this._visObs = seams.observeVisible(this, (visible) => this._post({ v: 1, kind: visible ? "resume" : "pause", payload: null }));
      }

      disconnectedCallback() {
        if (!this._worker) return;
        this._post({ v: 1, kind: "destroy", payload: null });
        this._sizeObs?.disconnect();
        this._visObs?.disconnect();
        this._worker.terminate();
        this._worker = null;
      }

      _measure() {
        const dpr = this._seams.devicePixelRatio ?? (typeof devicePixelRatio === "number" ? devicePixelRatio : 1);
        const r = this.getBoundingClientRect ? this.getBoundingClientRect() : { width: 0, height: 0 };
        return { w: Math.max(1, Math.round(r.width * dpr)), h: Math.max(1, Math.round(r.height * dpr)), dpr };
      }

      _post(msg, transfer) { this._worker?.postMessage(msg, transfer || []); }

      _onWorkerMessage(msg) {
        switch (msg.kind) {
          case "ready": this.dispatchEvent(new win.CustomEvent("sf:ready")); return;
          case "event": this.dispatchEvent(new win.CustomEvent("sf:event", { detail: JSON.parse(msg.payload) })); return;
          case "error": this.dispatchEvent(new win.CustomEvent("sf:error", { detail: msg.payload })); return;
        }
      }
    };
  }

  static install(win, seams) {
    if (win.customElements.get("sf-region")) return;
    win.customElements.define("sf-region", SfRegion.elementClass(win, seams));
  }
}
