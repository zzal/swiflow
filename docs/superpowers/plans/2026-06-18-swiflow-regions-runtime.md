# Swiflow Regions — Browser Runtime Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a `region(...)` actually run in the browser — ship the host-side runtime that turns an `<sf-region>` element into a worker-backed guest surface, wire the typed event payload across the existing dispatch path, and install the concrete decoder that satisfies Plan 1's `RegionEventDecoding` seam.

**Architecture:** Three Swift/driver edges plus one new JS module. (1) The JS driver's `serializeEvent` forwards a custom event's object `detail` as a JSON string; (2) `DispatcherBridge` reads it into `EventInfo.detail`; (3) a `SwiflowRegionDecoder` (JavaScriptKit `JSValueDecoder` + `JSON.parse`) is installed into `RegionDecoder.current` at mount. The new `js-driver/swiflow-regions.js` is an ES module that defines the `<sf-region>` custom element (main thread: owns the canvas, forwards props, observes size/visibility, relays events) and a worker-side `createGuestHost` (instantiates the guest ES module behind an `OffscreenCanvas`, translates the protocol). The element and host are written with **injectable seams** (worker factory, observers, scheduler, guest importer) so the whole runtime is unit-testable under `node:test` + jsdom without a real browser.

**Tech Stack:** ES modules + `node:test`/jsdom (`js-driver/test/`), JavaScriptKit (`JSValueDecoder`), the existing `serializeEvent`/`__swiflowDispatch`/`HandlerRegistry` dispatch path, `OffscreenCanvas` + module Web Workers (browser-only paths exercised in the deferred e2e).

**Depends on:** Plan 1 (`feat/swiflow-regions-design`) — `EventInfo.detail`, `RegionEventDecoding`/`RegionDecoder`, the `<sf-region>` lowering with `data-source` + `sfProps`, the `sf:event`/`sf:error` handler keys (centralized in `RegionWire`).

---

## The guest contract (the interface both the fake test guest and Plan 3's Rust SDK implement)

A guest is an **ES module** at the `data-source` URL. The worker `import()`s it and calls its **default export** as a factory:

```
factory(canvas: OffscreenCanvas, props: object | null, ctx: { emit, size }) -> guest
  ctx.emit(event: object): void   // guest → host; becomes a `sf:event`
  ctx.size: { w, h, dpr }         // initial device-pixel size

guest (returned object, all members optional except as noted):
  onProps(props: object): void
  onResize(w: number, h: number, dpr: number): void
  frame(dtMs: number): void       // if present, host runs a rAF loop
  destroy(): void
```

The host catches anything the factory throws and emits a `sf:error`. Pixels are entirely the guest's concern (its own WebGL/WebGPU/2D glue) — the host never touches the canvas after transfer.

---

## File Structure

**Created:**
- `js-driver/swiflow-regions.js` — the runtime: `SfRegion` element + `createGuestHost` + `runWorker`, all exported for tests; self-registers the element when loaded in a window.
- `js-driver/test/regions/host.test.js` — `createGuestHost` unit tests (pure node).
- `js-driver/test/regions/element.test.js` — `SfRegion` tests (jsdom + fake worker).
- `js-driver/test/regions/fixtures/fake-guest.js` — a tiny conforming guest for tests.
- `Sources/SwiflowDOM/RegionRuntime.swift` — `SwiflowRegionDecoder` (the concrete `RegionEventDecoding`).

**Modified:**
- `js-driver/swiflow-driver.js` — `serializeEvent` forwards object `detail`.
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated (driver edit).
- `examples/*/swiflow-driver.js` — re-copied from canonical (byte-equality gate).
- `Sources/SwiflowDOM/DispatcherBridge.swift` — read `payload.detail` into `EventInfo`.
- `Sources/SwiflowDOM/SwiflowDOM.swift` — install `RegionDecoder.current` in `render(into:)`.

---

# Phase A — The Swift / driver event-detail wire

## Task 1: `serializeEvent` forwards a custom event's object `detail`

**Files:**
- Modify: `js-driver/swiflow-driver.js` (`serializeEvent`, ~75-93)
- Test: `js-driver/test/regions/serialize-detail.test.js`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`; re-copy `examples/*/swiflow-driver.js`

- [ ] **Step 1: Write the failing test**

```javascript
// js-driver/test/regions/serialize-detail.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupDriver } from "../helpers.js";

describe("serializeEvent forwards object detail (regions)", () => {
  test("object detail on a CustomEvent is forwarded as a JSON string", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let payload = null;
    window.__swiflowDispatch = (_id, p) => { payload = p; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "sf-region" },
      { op: "addHandler", handle: 1, event: "sf:event", handlerId: 7 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("sf-region").dispatchEvent(
      new window.CustomEvent("sf:event", { detail: { kind: "select", id: 9 } })
    );
    assert.equal(payload.type, "sf:event");
    assert.equal(payload.detail, JSON.stringify({ kind: "select", id: 9 }));
    done();
  });

  test("a numeric detail (ordinary click) is NOT forwarded", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let payload = null;
    window.__swiflowDispatch = (_id, p) => { payload = p; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 8 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("button").click(); // click detail is a number
    assert.equal(payload.type, "click");
    assert.equal(payload.detail, null);
    done();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd js-driver && node --test test/regions/serialize-detail.test.js`
Expected: FAIL — `payload.detail` is `undefined`, not the JSON string / not `null`.

- [ ] **Step 3: Add `detail` to `serializeEvent`**

In `js-driver/swiflow-driver.js`, in the object returned by `serializeEvent`, add this property after `metaKey`:

```javascript
    // Custom events (e.g. a region's `sf:event`/`sf:error`) carry an object
    // `detail`; forward it as a JSON string so it can reach Swift through the
    // existing dispatch path. Ordinary DOM events whose `detail` is a number
    // (e.g. click count) are intentionally excluded.
    detail:
      event.detail !== null && typeof event.detail === "object"
        ? JSON.stringify(event.detail)
        : null,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd js-driver && node --test test/regions/serialize-detail.test.js`
Expected: PASS (both tests).

- [ ] **Step 5: Run the whole js-driver suite (no regressions)**

Run: `cd js-driver && npm test`
Expected: PASS. Then ADD the new file to the `test` script in `js-driver/package.json` (append `test/regions/serialize-detail.test.js` to the `node --test ...` list) and re-run `npm test` to confirm it's wired in.

- [ ] **Step 6: Regenerate the embedded driver and re-copy examples (the sync dance)**

Run, from repo root:
```bash
swift scripts/embed-driver.swift
for d in examples/*/; do [ -f "$d/swiflow-driver.js" ] && cp js-driver/swiflow-driver.js "$d/swiflow-driver.js"; done
```

- [ ] **Step 7: Confirm the byte-equality gates pass**

Run: `swift test --filter 'SwiflowCLITests.DriverEmbedderTests' && swift test --filter 'SwiflowCLITests.TemplatesTests'`
Expected: PASS (EmbeddedDriver is fresh; example drivers match canonical).

- [ ] **Step 8: Commit**

```bash
git add js-driver/swiflow-driver.js js-driver/package.json js-driver/test/regions/serialize-detail.test.js Sources/SwiflowCLI/EmbeddedDriver.swift examples/*/swiflow-driver.js
git commit -m "feat(driver): serializeEvent forwards object detail for region events"
```

---

## Task 2: `DispatcherBridge` reads `detail` into `EventInfo`

**Files:**
- Modify: `Sources/SwiflowDOM/DispatcherBridge.swift`

This is JavaScriptKit code (`#if canImport(JavaScriptKit)`), so it can't be unit-tested on macOS; it's covered by Task 1's JS test (the JS side) and the deferred browser e2e (the Swift side). Verify it compiles for wasm.

- [ ] **Step 1: Read the current `install()`**

Read `Sources/SwiflowDOM/DispatcherBridge.swift`. It reads named fields off `payload` (`payload.type.string`, etc.) and constructs `EventInfo(...)`.

- [ ] **Step 2: Add the `detail` read and pass it through**

After the `let metaKey = payload.metaKey.boolean ?? false` line, add:

```swift
            let detail = payload.detail.string
```

Then add `detail: detail,` to the `EventInfo(...)` initializer call (anywhere in the argument list; `detail` is the last parameter — put it after `metaKey: metaKey`).

- [ ] **Step 3: Verify the wasm cross-compile**

Run: `swift build --swift-sdk swift-6.3.2-RELEASE_wasm --target SwiflowDOM`
Expected: `Build complete`. (If the wasm SDK name differs locally, run `swift sdk list` and use the wasm SDK id.)

- [ ] **Step 4: Confirm host build + tests still green**

Run: `swift build && swift test --filter 'SwiflowTests'`
Expected: PASS (host build excludes the JSKit code; the core suite is unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowDOM/DispatcherBridge.swift
git commit -m "feat(dom): DispatcherBridge carries custom-event detail into EventInfo"
```

---

## Task 3: `SwiflowRegionDecoder` + install it at mount

**Files:**
- Create: `Sources/SwiflowDOM/RegionRuntime.swift`
- Modify: `Sources/SwiflowDOM/SwiflowDOM.swift` (`render(into:)`)

JavaScriptKit code — verified via wasm cross-compile, exercised in the deferred e2e.

- [ ] **Step 1: Create the concrete decoder**

```swift
// Sources/SwiflowDOM/RegionRuntime.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The concrete `RegionEventDecoding` for the browser: parse the JSON string
/// with the engine's native `JSON.parse`, then decode the resulting JSValue
/// into the typed `RegionEvent`/`RegionError` via JavaScriptKit's
/// `JSValueDecoder`. Installed into `RegionDecoder.current` at mount. Mirrors
/// the decode pattern in `SwiflowStore/PersistentStore.swift`.
struct SwiflowRegionDecoder: RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let parse = JSObject.global.JSON.object?.parse.function else {
            throw RegionError(code: "no-json", message: "JSON.parse unavailable")
        }
        let parsed = try parse.throws(json)
        return try JSValueDecoder().decode(E.self, from: parsed)
    }
}
#endif
```

- [ ] **Step 2: Install it in `render(into:)`**

In `Sources/SwiflowDOM/SwiflowDOM.swift`, inside `render(into:_:)`, immediately after the existing `DispatcherBridge.install()` line, add:

```swift
        RegionDecoder.current = SwiflowRegionDecoder()
```

(`RegionDecoder` is `@MainActor`; `render` is already `@MainActor`, so this is fine. It's idempotent — re-assigning the same decoder on a second root mount is harmless.)

- [ ] **Step 3: Verify the wasm cross-compile**

Run: `swift build --swift-sdk swift-6.3.2-RELEASE_wasm --target SwiflowDOM`
Expected: `Build complete`.

- [ ] **Step 4: Host build sanity**

Run: `swift build`
Expected: success (the new file is `#if canImport(JavaScriptKit)`-gated, excluded on host).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowDOM/RegionRuntime.swift Sources/SwiflowDOM/SwiflowDOM.swift
git commit -m "feat(dom): install SwiflowRegionDecoder into RegionDecoder.current at mount"
```

---

# Phase B — The JS regions runtime (node:test + jsdom)

> All of Phase B lives in `js-driver/swiflow-regions.js` and its tests. The module exports `createGuestHost`, `SfRegion`, and `runWorker` for testing, and self-registers `<sf-region>` only when `customElements`/`window` exist. Browser-only mechanisms (real `Worker`, `transferControlToOffscreen`, `import()` of the guest) are injected as seams so jsdom can exercise the logic with fakes.

## Task 4: `createGuestHost` — the worker-side protocol translator

**Files:**
- Create: `js-driver/swiflow-regions.js` (start it with `createGuestHost`)
- Create: `js-driver/test/regions/fixtures/fake-guest.js`
- Create: `js-driver/test/regions/host.test.js`

- [ ] **Step 1: Write the fake guest fixture**

```javascript
// js-driver/test/regions/fixtures/fake-guest.js
// A tiny conforming guest: records calls, echoes a prop change as an event.
export default function fakeGuest(canvas, props, ctx) {
  const calls = { props: [], resize: [], frames: 0, destroyed: false };
  // Echo the initial props count back as a "ready-count" event.
  if (props) ctx.emit({ kind: "init", count: props.count ?? 0 });
  return {
    onProps(p) { calls.props.push(p); ctx.emit({ kind: "prop", count: p.count ?? 0 }); },
    onResize(w, h, dpr) { calls.resize.push([w, h, dpr]); },
    frame(_dt) { calls.frames++; },
    destroy() { calls.destroyed = true; },
    _calls: calls, // test introspection only
  };
}
```

- [ ] **Step 2: Write the failing host tests**

```javascript
// js-driver/test/regions/host.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { createGuestHost } from "../../swiflow-regions.js";
import fakeGuest from "./fixtures/fake-guest.js";

function makeHost() {
  const posted = [];
  const host = createGuestHost({
    post: (m) => posted.push(m),
    importGuest: async (_source) => fakeGuest, // bypass real import()
  });
  return { host, posted };
}

describe("createGuestHost", () => {
  test("init imports the guest, emits ready, and forwards initial props", async () => {
    const { host, posted } = makeHost();
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: JSON.stringify({ count: 3 }), size: { w: 10, h: 10, dpr: 1 } } }, /*canvas*/ {});
    assert.ok(posted.some((m) => m.kind === "ready"));
    // the guest's init emit and any echoes arrive as "event" envelopes:
    const events = posted.filter((m) => m.kind === "event").map((m) => JSON.parse(m.payload));
    assert.deepEqual(events[0], { kind: "init", count: 3 });
  });

  test("props/resize/destroy reach the guest", async () => {
    const { host, posted } = makeHost();
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: null, size: { w: 1, h: 1, dpr: 1 } } }, {});
    host.handle({ v: 1, kind: "props", payload: JSON.stringify({ count: 5 }) });
    host.handle({ v: 1, kind: "resize", payload: { w: 20, h: 30, dpr: 2 } });
    const ev = posted.filter((m) => m.kind === "event").map((m) => JSON.parse(m.payload));
    assert.deepEqual(ev.at(-1), { kind: "prop", count: 5 });
    host.handle({ v: 1, kind: "destroy", payload: null });
    // a second props after destroy must be ignored (no throw, no event):
    const before = posted.length;
    host.handle({ v: 1, kind: "props", payload: JSON.stringify({ count: 9 }) });
    assert.equal(posted.length, before);
  });

  test("a guest factory that throws yields an error envelope, not a crash", async () => {
    const posted = [];
    const host = createGuestHost({
      post: (m) => posted.push(m),
      importGuest: async () => () => { throw new Error("boom"); },
    });
    await host.handle({ v: 1, kind: "init", payload: { source: "x", props: null, size: { w: 1, h: 1, dpr: 1 } } }, {});
    const err = posted.find((m) => m.kind === "error");
    assert.ok(err);
    assert.equal(err.payload.code, "init-failed");
  });
});
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd js-driver && node --test test/regions/host.test.js`
Expected: FAIL — `swiflow-regions.js` doesn't exist / `createGuestHost` is not exported.

- [ ] **Step 4: Implement `createGuestHost` (start the module)**

```javascript
// js-driver/swiflow-regions.js
//
// Swiflow Regions browser runtime. Load via <script type="module">. Defines the
// <sf-region> custom element (main thread) and the worker-side guest host. All
// three building blocks are exported for unit testing; the element self-registers
// only in a window context (Phase B Task 10 wires the real worker).

const PROTOCOL = 1;

// Worker-side: translate the protocol to/from a guest ES module instance.
// `deps.post(msg)` sends a host→? envelope; `deps.importGuest(source)` resolves
// the guest factory (real impl uses dynamic import()).
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
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd js-driver && node --test test/regions/host.test.js`
Expected: PASS (3 tests). Add this file + `test/regions/serialize-detail.test.js` (if not already) to `js-driver/package.json`'s `test` script.

- [ ] **Step 6: Commit**

```bash
git add js-driver/swiflow-regions.js js-driver/test/regions/ js-driver/package.json
git commit -m "feat(regions-js): worker-side createGuestHost protocol translator"
```

---

## Task 5: `SfRegion` element — connect/teardown with an injected worker

**Files:**
- Modify: `js-driver/swiflow-regions.js` (add `SfRegion`)
- Create: `js-driver/test/regions/element.test.js`

- [ ] **Step 1: Write the failing test (jsdom + fake worker)**

```javascript
// js-driver/test/regions/element.test.js
import { describe, test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { SfRegion } from "../../swiflow-regions.js";

class FakeWorker {
  constructor() { this.posted = []; this.terminated = false; this.onmessage = null; }
  postMessage(msg, _transfer) { this.posted.push(msg); }
  terminate() { this.terminated = true; }
  // test helper: simulate a worker → host message
  _send(msg) { this.onmessage?.({ data: msg }); }
}

function mountRegion() {
  const dom = new JSDOM(`<!DOCTYPE html><div id="app"></div>`, { runScripts: "outside-only" });
  const { window } = dom;
  const workers = [];
  // Register the element against THIS jsdom's HTMLElement with injected seams.
  SfRegion.install(window, {
    makeWorker: () => { const w = new FakeWorker(); workers.push(w); return w; },
    makeCanvas: () => ({ transferControlToOffscreen: () => ({ _offscreen: true }) }),
    schedule: (cb) => cb(),                 // run rAF-coalesced work synchronously
    observeSize: () => ({ disconnect() {} }),
    observeVisible: () => ({ disconnect() {} }),
  });
  const el = window.document.createElement("sf-region");
  el.setAttribute("data-source", "regions/scene.js");
  el.sfProps = JSON.stringify({ count: 1 });
  window.document.getElementById("app").appendChild(el);
  return { window, el, workers };
}

describe("SfRegion element", () => {
  test("connecting spawns a worker and posts init with source + props + size", () => {
    const { workers } = mountRegion();
    assert.equal(workers.length, 1);
    const init = workers[0].posted.find((m) => m.kind === "init");
    assert.ok(init, "expected an init message");
    assert.equal(init.payload.source, "regions/scene.js");
    assert.equal(init.payload.props, JSON.stringify({ count: 1 }));
    assert.ok(init.payload.size && typeof init.payload.size.w === "number");
  });

  test("disconnecting posts destroy and terminates the worker", () => {
    const { el, workers } = mountRegion();
    el.remove();
    assert.ok(workers[0].posted.some((m) => m.kind === "destroy"));
    assert.equal(workers[0].terminated, true);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: FAIL — `SfRegion` / `SfRegion.install` not found. (Ensure `jsdom` is a devDependency in `js-driver/package.json`; the existing tests already use it via `helpers.js`.)

- [ ] **Step 3: Implement `SfRegion` (append to `swiflow-regions.js`)**

```javascript
// --- Main-thread: the <sf-region> custom element ---
//
// Seams (all defaulted to real browser APIs by `defaultSeams`, overridden in tests):
//   makeWorker()        -> a Worker-like { postMessage, terminate, onmessage }
//   makeCanvas()        -> a <canvas> (or fake) exposing transferControlToOffscreen()
//   schedule(cb)        -> coalesce work to a frame (default: requestAnimationFrame)
//   observeSize(el, cb) -> { disconnect() }; calls cb(w, h, dpr) on resize
//   observeVisible(el, cb) -> { disconnect() }; calls cb(isVisible)

export class SfRegion {
  // Define the element class against a given window's HTMLElement, with seams.
  // Separated from `customElements.define` so tests can install into a jsdom window.
  static elementClass(win, seams) {
    return class SfRegionElement extends win.HTMLElement {
      connectedCallback() {
        if (this._worker) return; // idempotent / reconnection no-op
        this._seams = seams;
        this._propsLatest = this.sfProps ?? null;
        this._propsDirty = false;

        const canvas = seams.makeCanvas(this);
        if (canvas.style) { canvas.style.width = "100%"; canvas.style.height = "100%"; }
        this.appendChild?.(canvas);
        const offscreen = canvas.transferControlToOffscreen();

        const size = this._measure();
        this._worker = seams.makeWorker(this);
        this._worker.onmessage = (e) => this._onWorkerMessage(e.data);
        this._post(
          { v: 1, kind: "init", payload: { protocol: 1, source: this.getAttribute("data-source"), props: this._propsLatest, size } },
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
        const dpr = (this._seams.devicePixelRatio ?? (typeof devicePixelRatio === "number" ? devicePixelRatio : 1));
        const r = this.getBoundingClientRect ? this.getBoundingClientRect() : { width: 0, height: 0 };
        return { w: Math.max(1, Math.round(r.width * dpr)), h: Math.max(1, Math.round(r.height * dpr)), dpr };
      }

      _post(msg, transfer) {
        this._worker?.postMessage(msg, transfer || []);
      }

      _onWorkerMessage(msg) {
        switch (msg.kind) {
          case "ready": this.dispatchEvent(new win.CustomEvent("sf:ready")); return;
          case "event": this.dispatchEvent(new win.CustomEvent("sf:event", { detail: JSON.parse(msg.payload) })); return;
          case "error": this.dispatchEvent(new win.CustomEvent("sf:error", { detail: msg.payload })); return;
        }
      }
    };
  }

  // Test/seam-friendly install: register against a specific window.
  static install(win, seams) {
    if (win.customElements.get("sf-region")) return;
    win.customElements.define("sf-region", SfRegion.elementClass(win, seams));
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: PASS (2 tests). Add `test/regions/element.test.js` to `js-driver/package.json`'s `test` script.

- [ ] **Step 5: Commit**

```bash
git add js-driver/swiflow-regions.js js-driver/test/regions/element.test.js js-driver/package.json
git commit -m "feat(regions-js): SfRegion element connect/teardown over an injected worker"
```

---

## Task 6: Props forwarding — `sfProps` setter, frame-coalesced

**Files:**
- Modify: `js-driver/swiflow-regions.js` (add the `sfProps` property + coalescing)
- Modify: `js-driver/test/regions/element.test.js` (add a props test)

- [ ] **Step 1: Add the failing test**

```javascript
  test("setting sfProps after connect posts a single coalesced props message", () => {
    const { el, workers } = mountRegion(); // schedule(cb) runs synchronously in the fixture
    workers[0].posted.length = 0;          // ignore the init burst
    el.sfProps = JSON.stringify({ count: 2 });
    el.sfProps = JSON.stringify({ count: 3 });
    const props = workers[0].posted.filter((m) => m.kind === "props");
    assert.equal(props.length, 1, "two synchronous sets coalesce to one post");
    assert.equal(props[0].payload, JSON.stringify({ count: 3 }));
  });
```

(Note: the fixture's `schedule: (cb) => cb()` runs the coalescer immediately, so both sets within one synchronous turn collapse to the latest — which is exactly the per-frame semantics, made deterministic for the test.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: FAIL — setting `el.sfProps` posts nothing (it's just a field), so `props.length` is 0.

- [ ] **Step 3: Implement the coalescing `sfProps` property**

In `SfRegionElement` (inside `elementClass`), add a `sfProps` accessor and a coalescer. Add these members to the class:

```javascript
      get sfProps() { return this._propsValue ?? null; }
      set sfProps(v) {
        this._propsValue = v;
        if (!this._worker) return; // pre-connect: connect() reads _propsLatest from this
        this._propsLatest = v;
        if (this._propsDirty) return;
        this._propsDirty = true;
        this._seams.schedule(() => {
          this._propsDirty = false;
          if (this._worker) this._post({ v: 1, kind: "props", payload: this._propsLatest });
        });
      }
```

And in `connectedCallback`, change `this._propsLatest = this.sfProps ?? null;` to read the backing field directly: `this._propsLatest = this._propsValue ?? null;` (so a value set before connect is used in `init`).

- [ ] **Step 4: Run to verify it passes**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add js-driver/swiflow-regions.js js-driver/test/regions/element.test.js
git commit -m "feat(regions-js): coalesced sfProps forwarding to the worker"
```

---

## Task 7: Events-out routing — worker → CustomEvent

**Files:**
- Modify: `js-driver/test/regions/element.test.js` (add event-routing tests)
- (Source already implemented in Task 5's `_onWorkerMessage`; this task proves it.)

- [ ] **Step 1: Add the tests**

```javascript
  test("worker 'event' becomes a sf:event CustomEvent with parsed detail", () => {
    const { el, workers } = mountRegion();
    let got = null;
    el.addEventListener("sf:event", (e) => { got = e.detail; });
    workers[0]._send({ v: 1, kind: "event", payload: JSON.stringify({ kind: "select", id: 9 }) });
    assert.deepEqual(got, { kind: "select", id: 9 });
  });

  test("worker 'ready' and 'error' map to sf:ready / sf:error", () => {
    const { el, workers } = mountRegion();
    let ready = false, err = null;
    el.addEventListener("sf:ready", () => { ready = true; });
    el.addEventListener("sf:error", (e) => { err = e.detail; });
    workers[0]._send({ v: 1, kind: "ready", payload: { protocol: 1 } });
    workers[0]._send({ v: 1, kind: "error", payload: { code: "init-failed", message: "boom" } });
    assert.equal(ready, true);
    assert.deepEqual(err, { code: "init-failed", message: "boom" });
  });
```

- [ ] **Step 2: Run to verify it passes (already implemented)**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: PASS. (If a test fails, the bug is in `_onWorkerMessage` from Task 5 — fix it there.)

- [ ] **Step 3: Commit**

```bash
git add js-driver/test/regions/element.test.js
git commit -m "test(regions-js): cover worker→CustomEvent routing"
```

---

## Task 8: Resize broadcast — device-pixel size, coalesced

**Files:**
- Modify: `js-driver/swiflow-regions.js` (default `observeSize` seam) + the `defaultSeams` (Task 10) will wire the real `ResizeObserver`; here we prove the element posts what the seam reports.
- Modify: `js-driver/test/regions/element.test.js`

- [ ] **Step 1: Add the failing test (drive the size callback via the seam)**

```javascript
  test("a size-observer callback posts a resize with device pixels", () => {
    let sizeCb = null;
    const dom = new JSDOM(`<!DOCTYPE html><div id="app"></div>`);
    const { window } = dom;
    const workers = [];
    SfRegion.install(window, {
      makeWorker: () => { const w = new FakeWorker(); workers.push(w); return w; },
      makeCanvas: () => ({ transferControlToOffscreen: () => ({}) }),
      schedule: (cb) => cb(),
      observeSize: (_el, cb) => { sizeCb = cb; return { disconnect() {} }; },
      observeVisible: () => ({ disconnect() {} }),
    });
    const el = window.document.createElement("sf-region");
    el.setAttribute("data-source", "g.js");
    window.document.getElementById("app").appendChild(el);
    workers[0].posted.length = 0;
    sizeCb(640, 480, 2); // device-pixel-content-box already × dpr
    const resize = workers[0].posted.find((m) => m.kind === "resize");
    assert.deepEqual(resize.payload, { w: 640, h: 480, dpr: 2 });
  });
```

- [ ] **Step 2: Run to verify it passes (wiring from Task 5 already forwards observeSize)**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: PASS. The `observeSize` seam from Task 5's `connectedCallback` already posts `{kind:"resize", payload:{w,h,dpr}}`. If it doesn't, align `connectedCallback` to call `cb(w,h,dpr)` → post resize.

- [ ] **Step 3: Commit**

```bash
git add js-driver/test/regions/element.test.js
git commit -m "test(regions-js): cover device-pixel resize broadcast"
```

---

## Task 9: Pause / resume on visibility

**Files:**
- Modify: `js-driver/test/regions/element.test.js`
- (Source from Task 5's `observeVisible` wiring; this proves it.)

- [ ] **Step 1: Add the failing test**

```javascript
  test("visibility observer drives pause/resume posts", () => {
    let visCb = null;
    const dom = new JSDOM(`<!DOCTYPE html><div id="app"></div>`);
    const { window } = dom;
    const workers = [];
    SfRegion.install(window, {
      makeWorker: () => { const w = new FakeWorker(); workers.push(w); return w; },
      makeCanvas: () => ({ transferControlToOffscreen: () => ({}) }),
      schedule: (cb) => cb(),
      observeSize: () => ({ disconnect() {} }),
      observeVisible: (_el, cb) => { visCb = cb; return { disconnect() {} }; },
    });
    const el = window.document.createElement("sf-region");
    el.setAttribute("data-source", "g.js");
    window.document.getElementById("app").appendChild(el);
    workers[0].posted.length = 0;
    visCb(false);
    visCb(true);
    const kinds = workers[0].posted.map((m) => m.kind);
    assert.deepEqual(kinds, ["pause", "resume"]);
  });
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd js-driver && node --test test/regions/element.test.js`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add js-driver/test/regions/element.test.js
git commit -m "test(regions-js): cover pause/resume on visibility"
```

---

## Task 10: Real-browser wiring — `defaultSeams`, `runWorker`, self-registration

**Files:**
- Modify: `js-driver/swiflow-regions.js` (add `defaultSeams`, `runWorker`, the auto-register block)

This task adds the browser-only glue the seams abstracted away. It is exercised by the deferred e2e (Phase C), not by `node:test` — so verify it parses and the existing unit tests still pass.

- [ ] **Step 1: Add `defaultSeams`, `runWorker`, and self-registration**

Append to `js-driver/swiflow-regions.js`:

```javascript
// Real browser seams. The worker re-imports THIS module and calls runWorker().
function defaultSeams(win) {
  return {
    makeWorker: () => {
      const src = `import { runWorker } from ${JSON.stringify(import.meta.url)}; runWorker();`;
      const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
      return new win.Worker(url, { type: "module" });
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
// loop to a createGuestHost; the first message MUST be the init carrying the
// transferred OffscreenCanvas in its ports/data.
export function runWorker() {
  let canvas = null;
  const host = createGuestHost({
    post: (m) => self.postMessage(m),
    importGuest: (source) => import(source).then((m) => m.default),
  });
  self.onmessage = (e) => {
    const msg = e.data;
    if (msg.kind === "init" && msg.canvas) canvas = msg.canvas;
    host.handle(msg, canvas);
  };
}

// Auto-register in a window context (no-op in the worker / in node).
if (typeof window !== "undefined" && window.customElements) {
  SfRegion.install(window, defaultSeams(window));
}
```

Note for the implementer: the `init` message must carry the `OffscreenCanvas` so `runWorker` can hand it to the host. Update `SfRegionElement.connectedCallback`'s init post to include the offscreen canvas in the message body (`payload`/a `canvas` field) AND in the transfer list, e.g. `this._post({ v:1, kind:"init", canvas: offscreen, payload: {...} }, [offscreen])`. Adjust the Task 4 `host.handle` `init` branch to read `canvas` from the message if present (it already receives `canvas` as its 2nd arg in tests; in the real worker `runWorker` passes the stored `canvas`). Keep the unit tests green.

- [ ] **Step 2: Verify the module still parses and all unit tests pass**

Run: `cd js-driver && node --test test/regions/host.test.js test/regions/element.test.js`
Expected: PASS (all Phase B tests). The `import.meta.url` / `self` / `window` references are guarded and don't execute under node:test (the module is imported, the window-guard is false, `runWorker` isn't called).

- [ ] **Step 3: Lint-parse check**

Run: `cd js-driver && node --check swiflow-regions.js`
Expected: no output (syntax OK).

- [ ] **Step 4: Commit**

```bash
git add js-driver/swiflow-regions.js
git commit -m "feat(regions-js): real-browser seams, runWorker, and <sf-region> self-registration"
```

---

## Exit criteria (Plan 2)

- `serializeEvent` forwards object `detail` (and only object detail) — covered by `node:test`; the embedded driver + example copies are regenerated and the byte-equality gates pass.
- `DispatcherBridge` carries `detail` into `EventInfo`, and `SwiflowRegionDecoder` is installed at mount — both compile under the wasm SDK.
- `createGuestHost` translates init/props/resize/pause/resume/destroy to a guest and relays `emit`/errors — covered by `node:test`.
- `SfRegion` spawns a worker, forwards coalesced props, broadcasts device-pixel resize, pauses off-screen, relays `ready`/`event`/`error` as CustomEvents, and tears the worker down on disconnect — covered by `node:test` + jsdom with injected seams.
- `swiflow-regions.js` parses clean and the real-browser seams (`defaultSeams`/`runWorker`/blob module worker) are wired (exercised in the Phase C e2e).
- `cd js-driver && npm test` is green (all new region suites added to the `test` script).

## Handoff — Phase C (the Plan 2 ↔ Plan 3 integration, NOT built here)

A meaningful real-browser e2e needs a *real guest drawing pixels*, which is Plan 3 (the Rust guest SDK + reference guest). So the following are deliberately deferred to the integration step that lands with Plan 3:

1. **Distribution.** Teach the CLI to ship `swiflow-regions.js`: extend `scripts/embed-driver.swift` + `EmbeddedDriver.swift` with a `regionsSource` (and a byte-equality test mirroring `DriverEmbedderTests`), have `swiflow init`/the dev server write it, add `<script type="module" src="swiflow-regions.js">` to the HTML template, and `cp` it to the region-using example(s). (Until then, the runtime is unit-tested but not auto-served.)
2. **Guests + example.** A `RegionDemo` example whose app renders a region, plus guest modules under `public/regions/`. Two guests, in order:
   - **(first, real-world) Conway's Game of Life** — the canonical [`rustwasm/wasm_game_of_life`](https://github.com/rustwasm/wasm_game_of_life) Rust→Wasm module, reused **unmodified**, to prove Regions hosts external compiled wasm we didn't write. Its `Universe` is **DOM-free pure compute** (it never touches `document`/`window`), which is exactly why it runs in our worker — the ~30-line adapter instantiates the published wasm, ticks it per `frame`, reads the cell bitmap from `wasm.memory`, and draws to the OffscreenCanvas. Vendor a prebuilt `wasm-pack --target web` artifact into `examples/RegionDemo/public/regions/game-of-life/` (checked in for reproducibility; record the source commit + build command).
   - **(then) the Rust reference guest** from Plan 3's SDK (the `#[region]`-macro path) — the first-party "draws into the OffscreenCanvas via the SDK" example.

   The adapter (the guest ES module the worker imports) conforms to the guest contract. Sketch:

   ```javascript
   // examples/RegionDemo/public/regions/game-of-life/adapter.js  (default export = guest factory)
   import init, { Universe } from "./wasm_game_of_life.js"; // wasm-pack --target web ESM; no DOM touched
   export default async function gameOfLife(canvas, props, ctx) {
     const wasm = await init();                 // exposes wasm.memory
     const u = Universe.new();
     const w = u.width(), h = u.height();
     const cell = props?.cellSize ?? 6;
     canvas.width = w * cell; canvas.height = h * cell;
     const g = canvas.getContext("2d");
     let speed = props?.speed ?? 1, gen = 0;
     const draw = () => {
       const cells = new Uint8Array(wasm.memory.buffer, u.cells(), Math.ceil((w * h) / 8));
       g.fillStyle = "#fff"; g.fillRect(0, 0, canvas.width, canvas.height);
       g.fillStyle = "#111";
       for (let i = 0; i < w * h; i++)
         if ((cells[i >> 3] >> (i & 7)) & 1) g.fillRect((i % w) * cell, ((i / w) | 0) * cell, cell, cell);
     };
     return {
       onProps(p) { if (p.speed != null) speed = p.speed; },
       frame() { for (let i = 0; i < speed; i++) { u.tick(); gen++; } draw();
                 if (gen % 64 === 0) ctx.emit({ kind: "generation", value: gen }); },
       destroy() { u.free?.(); },
     };
   }
   ```
   (The exact cell bit-layout is `wasm_game_of_life`-version-specific — confirm against the vendored build; the bit-packed `cells()` layout is the book's "exercise" version.)

   The Swift side declares the guest (no annotation needed thanks to Plan 1's inference):

   ```swift
   struct GoLProps: Encodable { var speed: Int; var cellSize: Int }
   struct GoLEvent: RegionEvent { let kind: String; let value: Int }
   enum GameOfLife: RegionGuest {
       typealias Props = GoLProps; typealias Event = GoLEvent
       static let source = "regions/game-of-life/adapter.js"
   }
   // in the demo body:
   region(GameOfLife.self, key: "life", props: GoLProps(speed: 1, cellSize: 6))
       .onEvent { e in generation = e.value }   // e: GoLEvent inferred
       .fill()
   ```

3. **Playwright e2e** (`Tests/playwright/`, via `swiflow dev`): mount the demo and assert the worker boots and `sf:ready` fires, the Game-of-Life canvas advances (a `generation` `sf:event` reaches `@State` → the page shows an incrementing counter), the region pauses when scrolled off-screen, and an induced failure (bad `data-source`) dispatches `sf:error` → sibling fallback. Then verify **HMR survival**: edit the Swift app and save; the worker is NOT re-created and the generation counter keeps climbing from where it was (Plan 1's keyed diff provides this — no Plan 2 code, but prove it). Remember: `swift build -c release --product swiflow` before running the harness (it reuses a stale CLI otherwise).
4. **Decoder + DispatcherBridge** get their real-browser coverage here (they can't be `swift test`ed on macOS).
5. **Adapter recipe in the SDK (Plan 3).** Generalize the Game-of-Life adapter into a documented "wrap an external wasm module as a guest" recipe, so hosting third-party wasm is a first-class ~30-line path. **Guest-shape doctrine to document:** Regions host *component-shaped* guests (accept a canvas, no global `document`/`window`/audio, controls via props). *App-shaped* modules that own the page — e.g. `waltonseymour/visualizer`, whose Rust `run()` grabs the DOM canvas by id, owns the `AudioContext` + rAF loop, and reads `window.*` controls — are NOT worker-hostable without a fork; they're the use case for the deferred **main-thread mode** + **data channel** (audio captured host-side, frames streamed in).

## Open questions for the implementer

- **Module-worker + blob URL support:** `new Worker(blobURL, { type: "module" })` with a dynamic `import()` of an absolute guest URL is the assumed path. If a target browser balks, the fallback is shipping `swiflow-regions-worker.js` as a second served asset (adds a distribution edge in Phase C). Decide during the Phase C e2e.
- **`devicePixelContentBoxSize` fallback:** the `defaultSeams` resize path falls back to `contentBoxSize × devicePixelRatio`; on that path, also listen to `matchMedia('(resolution: …dppx)')` for DPR-only changes (zoom/monitor move) — add when the e2e shows it's needed.
- **HMR survival** (keep the worker alive when `data-source`+`key` are unchanged) is provided by Plan 1's keyed diff (the element isn't re-created), so no Plan 2 code is required — but verify it in the Phase C e2e (save → guest state preserved).
