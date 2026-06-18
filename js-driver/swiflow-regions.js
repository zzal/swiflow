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

  return { handle };
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
      get sfProps() { return this._propsValue ?? null; }
      set sfProps(v) {
        this._propsValue = v;
        if (!this._worker) return; // pre-connect: connectedCallback reads _propsValue
        this._propsLatest = v;
        if (this._propsDirty) return;
        this._propsDirty = true;
        this._seams.schedule(() => {
          this._propsDirty = false;
          if (this._worker) this._post({ v: 1, kind: "props", payload: this._propsLatest });
        });
      }

      connectedCallback() {
        if (this._worker) return; // idempotent / reconnection no-op
        this._seams = seams;
        this._propsLatest = this._propsValue ?? null;
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
        if (this._worker._sfBlobUrl) URL.revokeObjectURL(this._worker._sfBlobUrl);
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
          // msg.payload is the {code,message} object; serializeEvent JSON-stringifies it,
          // DispatcherBridge reads it as a String, and SwiflowRegionDecoder JSON.parses + decodes RegionError.
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

// Real browser seams. The worker re-imports THIS module and calls runWorker().
function defaultSeams(win) {
  return {
    makeWorker: () => {
      const src = `import { runWorker } from ${JSON.stringify(import.meta.url)}; runWorker();`;
      const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
      const w = new win.Worker(url, { type: "module" });
      w._sfBlobUrl = url; // revoked in disconnectedCallback (see SfRegion) — avoids a per-mount leak
      return w;
    },
    makeCanvas: () => win.document.createElement("canvas"),
    schedule: (cb) => win.requestAnimationFrame(cb),
    devicePixelRatio: undefined, // read live in _measure
    observeSize: (el, cb) => {
      const ro = new win.ResizeObserver((entries) => {
        const e = entries[0];
        const box = e.devicePixelContentBoxSize?.[0];
        if (box) { cb(box.inlineSize, box.blockSize, win.devicePixelRatio || 1); return; }
        const c = e.contentBoxSize?.[0] ?? { inlineSize: el.clientWidth, blockSize: el.clientHeight };
        const dpr = win.devicePixelRatio || 1;
        // NOTE (deferred to Phase C / older-Safari only): on this fallback path a DPR-only
        // change (zoom / monitor move) won't fire the ResizeObserver; a matchMedia('(resolution: …dppx)')
        // listener is needed to re-broadcast. Tracked in the design spec's deferred scope.
        cb(Math.max(1, Math.round(c.inlineSize * dpr)), Math.max(1, Math.round(c.blockSize * dpr)), dpr);
      });
      try { ro.observe(el, { box: "device-pixel-content-box" }); } catch { ro.observe(el); }
      return ro;
    },
    observeVisible: (el, cb) => {
      const io = new win.IntersectionObserver((es) => cb(es[0].isIntersecting && !win.document.hidden));
      io.observe(el);
      const onVis = () => cb(!win.document.hidden);
      win.document.addEventListener("visibilitychange", onVis);
      return { disconnect() { io.disconnect(); win.document.removeEventListener("visibilitychange", onVis); } };
    },
  };
}

// Worker entry: re-imported in the worker via the blob above. Wires the message
// loop to a createGuestHost; the init message carries the transferred
// OffscreenCanvas as `msg.canvas`.
export function runWorker() {
  let canvas = null;
  const host = createGuestHost({
    post: (m) => self.postMessage(m),
    importGuest: (source) => import(source).then((m) => m.default),
  });
  self.onmessage = (e) => {
    const msg = e.data;
    if (msg.kind === "init") {
      if (!msg.canvas) {
        self.postMessage({ v: 1, kind: "error", payload: { code: "no-canvas", message: "init missing OffscreenCanvas" } });
        return;
      }
      canvas = msg.canvas;
    }
    host.handle(msg, canvas);
  };
}

// Auto-register in a window context (no-op in the worker / in node).
if (typeof window !== "undefined" && window.customElements) {
  SfRegion.install(window, defaultSeams(window));
}
