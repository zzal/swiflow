# Swiflow Regions — JS Guest SDK (`canvasGuest`) Design

**Status:** Design (brainstormed 2026-06-19)

**Goal:** A small JS helper, `canvasGuest`, that absorbs the per-guest `adapter.js`
boilerplate so a guest author writes only their compute + draw — not the factory
wiring, dpr-crisp canvas sizing, resize→grid reflow, fps bookkeeping, or lifecycle.
It is the first concrete piece of the "Guest authoring (the SDK)" scope deferred
from the Regions design (`docs/superpowers/specs/2026-06-18-swiflow-regions-design.md:188`).

**Non-goals (this pass):** the `swiflow region <Name>` scaffold generator, the Rust
`#[region]` proc-macro, and non-JS guest SDKs (AssemblyScript/C/Zig). They remain
the later layers; this pass is the JS shim only. The raw `(canvas, props, ctx) =>
guest` contract is **unchanged** and stays as the escape hatch for WebGL / non-2D /
advanced guests — `canvasGuest` is a convenience *on top* of it, not a replacement.

---

## The decisions (from brainstorming)

1. **Canvas-2D helper** — opinionated about the OffscreenCanvas 2D context; not a
   general renderer-agnostic lifecycle.
2. **Raster + opt-in grid** — `cellSize` present ⇒ grid mode; absent ⇒ raster.
3. **Separate embedded asset** — `js-driver/swiflow-region-guest.js`, embedded into
   the CLI and written by `swiflow init` exactly like `swiflow-regions.js`; the
   adapter imports it by relative path.
4. **Flat `(state, ctx)` hooks** — `setup` returns `state`; every other hook is a
   testable function of `(state, ctx)`.

---

## API

```js
import { canvasGuest } from "../../swiflow-region-guest.js";

export default canvasGuest({
  cellSize: 6,                 // present → grid mode; omit → raster mode
  async setup(ctx) { … },      // load compute, return `state`
  resize(state, ctx) { … },    // optional; fired only on a real grid/size change
  frame(state, ctx) { … },     // draw one frame
  onProps(state, props) { … }, // optional
  destroy(state) { … },        // optional
});
```

`canvasGuest(config)` returns a guest factory `(canvas, props, hostCtx) => guest`
conforming to the existing contract — so the worker host loads it unchanged.

### Hook context (`ctx`)

| Hook | `ctx` fields |
|---|---|
| `setup` | `{ props, emit }` — returns `state` (sync or `Promise`) |
| `resize` | grid: `{ cols, rows, cell, dpr, emit }` · raster: `{ width, height, dpr, emit }` |
| `frame` | `{ ctx2d, dt, fps, dpr, emit }` + (grid: `{ cols, rows, cell }` · raster: `{ width, height }`) |
| `onProps` | `(state, props)` — parsed props object |
| `destroy` | `(state)` |

- The shim receives the region's **measured device size** `(w, h, dpr)` from the
  host's `onResize`. `cell = round(cellSize × dpr)` (device px per cell).
  - **Grid mode:** `cols = floor(w / dpr / cellSize)`, `rows = floor(h / dpr /
    cellSize)` (min 8×8); the canvas **buffer** is sized to `cols·cell × rows·cell`,
    so `fillRect((i % cols)·cell, (i / cols | 0)·cell, cell, cell)` is retina-crisp.
  - **Raster mode:** the canvas buffer is `w × h` (no grid snapping).
- In `frame`/`resize`, grid hooks receive `{ cols, rows, cell }`; raster hooks
  receive `{ width, height, dpr }` — the buffer size in device pixels.

### What the shim owns

- The `(canvas, props, hostCtx)` factory wiring and the returned guest object.
- The OffscreenCanvas **2D context** (`canvas.getContext("2d")`).
- **dpr-crisp sizing** of the canvas buffer.
- **Reflow detection** — translates the raw `onResize(w, h, dpr)` into a `resize`
  hook call **only when** `cols`/`rows` (grid) or `width`/`height` (raster) or `dpr`
  actually change. A pure-dpr change re-sizes + redraws without re-firing layout.
- The **fps EMA** (`fps = fps*0.9 + (1000/dt)*0.1`), exposed as `ctx.fps`.
- **Lifecycle** — `destroy` plumbing. `setup` and the **initial** `resize` run inside
  the factory, so a throw there becomes the host's `init-failed`; `frame` throws
  become `frame-failed` (both already handled by the host). Later `onResize`/
  `onProps`/`destroy` calls — which the host does *not* guard — are wrapped so a hook
  bug `console.warn`s instead of throwing uncaught into the worker message handler.

### Opinionations

- **`resize` fires only on real change** (not every ResizeObserver tick). First
  mount counts as a change, so `resize` is the canonical "build for this size" hook.
- **fps is exposed, never auto-drawn.** The shim computes it; the author draws it (or
  not). The shim never paints over guest pixels.
- **No reset/seed concept.** That's guest app-logic. A guest re-seeds inside its own
  `resize` (size changed) and detects a prop-token change in `onProps` (see the GoL
  migration below). The shim stays domain-agnostic.

---

## RegionDemo migration (the first consumer)

`examples/RegionDemo/regions/game-of-life/adapter.js` is rewritten onto `canvasGuest`.
The ~90-line hand-rolled `makeGuest` (dpr/sizing/reflow/fps/factory) collapses; only
the Game-of-Life logic remains (~30 lines):

```js
import { canvasGuest } from "../../swiflow-region-guest.js";

async function loadUniverse() {
  const res = await fetch(new URL("./universe.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(),
    { env: { abort() { throw new Error("AssemblyScript abort()"); } } });
  return instance.exports;
}

export default canvasGuest({
  cellSize: 6,
  async setup() { return { ex: await loadUniverse(), seed: 0, gen: 0, reseed: false }; },
  resize(s, { cols, rows }) { s.ex.init(cols, rows, s.seed); s.gen = 0; },
  onProps(s, p) { if (p && p.reset !== s.seed) { s.seed = p.reset; s.reseed = true; } },
  frame(s, { ctx2d, cols, rows, cell, fps, emit }) {
    if (s.reseed) { s.ex.init(cols, rows, s.seed); s.gen = 0; s.reseed = false; }
    s.ex.tick(); s.gen++;
    drawCells(ctx2d, s.ex, cols, rows, cell);
    drawFps(ctx2d, fps, cell);
    if (s.gen % 64 === 0) emit({ kind: "generation", value: s.gen });
  },
});
```

(`drawCells`/`drawFps` are small local helpers — the actual rendering, which is the
only thing the shim can't own.) The GoL-specific reset/generation logic stays put;
the plumbing is gone.

---

## Distribution

Mirrors `swiflow-regions.js` exactly:

- **Canonical:** `js-driver/swiflow-region-guest.js`.
- **Embedded:** a new `EmbeddedDriver.guestSdkSource` constant, generated by
  `scripts/embed-driver.swift` (which already reads driver/sw/regions); the
  `DriverEmbedder` freshness test gains a matching assertion.
- **Scaffolded:** `ProjectWriter` writes `swiflow-region-guest.js` next to
  `swiflow-regions.js` on `swiflow init`.
- **Synced:** committed copies in the example trees that use it (RegionDemo) stay
  byte-equal to the canonical (same pattern/test as the other runtime assets).
- **Imported:** the adapter resolves `../../swiflow-region-guest.js` relative to its
  own (absolutized) module URL → served at the app root.

No new HTML `<script>` is needed — the shim is imported by the guest module in the
worker, not loaded on the main thread.

---

## Testing

- **`js-driver/test/regions/guest-sdk.test.js`** (node:test) — drive `canvasGuest`
  with a fake canvas (`getContext` → fake 2D ctx) and a fake host ctx (`{ emit,
  size }`):
  - grid mode computes `cols/rows/cell` from size + `cellSize` (incl. the 8×8 clamp);
  - `resize` fires on first mount and on a cols/rows change, **and is skipped** on a
    no-op resize and on a pure-dpr change (canvas still re-sized, board not rebuilt);
  - `frame` forwards `{ ctx2d, cols, rows, cell, dt, fps }`; fps EMA converges for a
    fixed `dt`;
  - raster mode (no `cellSize`) forwards `{ width, height, dpr }`;
  - `onProps`/`destroy` reach the user hooks; a throw in a later `onResize`/`onProps`/
    `destroy` is caught + logged (spy on `console.warn`), not propagated.
- **RegionDemo:** the existing `adapter.test.js` is refocused — the draw/tick/reflow
  assertions move to the shim test; what remains is the GoL hooks (reseed-on-resize,
  reset-token, generation emit) tested against a fake `ex`. `universe-wasm.test.js`
  is unchanged. `region.spec.ts` (the browser e2e) is unchanged and must still pass —
  it proves the rewritten adapter still round-trips.

---

## File structure

**Create**
- `js-driver/swiflow-region-guest.js` — the shim.
- `js-driver/test/regions/guest-sdk.test.js` — shim unit tests.

**Modify**
- `examples/RegionDemo/regions/game-of-life/adapter.js` — rewrite onto `canvasGuest`.
- `examples/RegionDemo/swiflow-region-guest.js` — new committed copy (synced).
- `js-driver/test/regions/adapter.test.js` — refocus onto the remaining GoL hooks.
- `scripts/embed-driver.swift`, `Sources/SwiflowCLI/DriverEmbedder.swift`,
  `Sources/SwiflowCLI/EmbeddedDriver.swift`, `Sources/SwiflowCLI/Project/ProjectWriter.swift`,
  `Tests/SwiflowCLITests/DriverEmbedderTests.swift` — thread `guestSdkSource` through
  the embed + scaffold pipeline (same shape as `regionsSource`).

---

## Out of scope / future layers

- `swiflow region <Name>` scaffold generator (emits the Swift `RegionGuest` stub +
  an adapter skeleton on the shim).
- Rust `#[region]` proc-macro + crate; AssemblyScript/C/Zig guest SDKs.
- A WebGL convenience (`webglGuest`) — the raw contract covers it until then.
