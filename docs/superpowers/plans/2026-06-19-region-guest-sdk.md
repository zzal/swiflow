# Region Guest SDK (`canvasGuest`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `canvasGuest` — a JS guest-SDK shim that absorbs the per-guest
`adapter.js` boilerplate (factory wiring, dpr-crisp canvas sizing, resize→grid
reflow, fps, lifecycle) so a Regions guest author writes only `setup()` + a draw.

**Architecture:** A new canonical asset `js-driver/swiflow-region-guest.js` exports
`canvasGuest(config)`, which returns a conforming `(canvas, props, host) => guest`
factory. It is **raster** by default and switches to **grid** mode when `cellSize`
is set. It is embedded into the CLI and scaffolded by `swiflow init` exactly like
`swiflow-regions.js`. `examples/RegionDemo`'s adapter is migrated onto it as the
first consumer. The raw guest contract is unchanged and remains the escape hatch.

**Tech Stack:** ES modules; `node:test` + a tiny fake canvas/ctx (no jsdom needed);
the Swift CLI embed pipeline (`scripts/embed-driver.swift` + `DriverEmbedder` +
`ProjectWriter`); Playwright for the unchanged e2e.

**Spec:** `docs/superpowers/specs/2026-06-19-region-guest-sdk-design.md`.

---

## File Structure

**Create**
- `js-driver/swiflow-region-guest.js` — the shim (`canvasGuest`). One responsibility:
  turn a hook config into a guest factory.
- `js-driver/test/regions/guest-sdk.test.js` — shim unit tests (raster + grid).

**Modify**
- `js-driver/package.json` — register `guest-sdk.test.js` in the `test` script.
- `scripts/embed-driver.swift` — read `swiflow-region-guest.js`, emit `guestSdkSource`.
- `Sources/SwiflowCLI/DriverEmbedder.swift` — add `guestSdkJS` param + the constant.
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated (adds `guestSdkSource`).
- `Sources/SwiflowCLI/Project/ProjectWriter.swift` — add `jsGuestSdkSource` param,
  write `swiflow-region-guest.js`.
- `Sources/SwiflowCLI/Commands/InitCommand.swift` — pass `EmbeddedDriver.guestSdkSource`.
- `Tests/SwiflowCLITests/DriverEmbedderTests.swift` — freshness test + 2 `swiftSource`
  call sites.
- `Tests/SwiflowCLITests/{DevCommandTests,BuildCommandTests,InitCommandTests}.swift`
  and `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift` — `writeProject`
  call sites gain `jsGuestSdkSource`.
- `examples/RegionDemo/swiflow-region-guest.js` — new committed copy (synced).
- `examples/RegionDemo/regions/game-of-life/adapter.js` — rewritten onto `canvasGuest`.
- `js-driver/test/regions/adapter.test.js` — refocused onto the GoL hooks.

---

# Task 1: `canvasGuest` — raster mode + lifecycle + fps

**Files:**
- Create: `js-driver/swiflow-region-guest.js`
- Test: `js-driver/test/regions/guest-sdk.test.js`
- Modify: `js-driver/package.json`

- [ ] **Step 1: Write the failing tests** — `js-driver/test/regions/guest-sdk.test.js`

```js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { canvasGuest } from "../../swiflow-region-guest.js";

// Minimal fakes: the shim never draws itself — it only gets the 2D context and
// passes it through — so the ctx is an opaque marker.
function fakeCanvas() {
  const ctx2d = { _is: "ctx2d" };
  return { width: 0, height: 0, getContext: () => ctx2d, _ctx: ctx2d };
}
function fakeHost(size) {
  const events = [];
  return { emit: (e) => events.push(e), size, _events: events };
}

describe("canvasGuest — raster mode", () => {
  test("setup runs; initial resize fires with device dims; frame forwards ctx2d/dims/dt/fps", async () => {
    const calls = { setup: 0, resize: [], frame: [] };
    const factory = canvasGuest({
      async setup({ props }) { calls.setup++; return { props }; },
      resize(s, c) { calls.resize.push([c.width, c.height, c.dpr]); },
      frame(s, c) { calls.frame.push(c); },
    });
    const canvas = fakeCanvas();
    const guest = await factory(canvas, { a: 1 }, fakeHost({ w: 200, h: 100, dpr: 2 }));
    assert.equal(calls.setup, 1);
    assert.deepEqual(calls.resize, [[200, 100, 2]]);
    assert.equal(canvas.width, 200);   // raster buffer = device size
    assert.equal(canvas.height, 100);
    guest.frame(16);
    const f = calls.frame.at(-1);
    assert.equal(f.ctx2d, canvas._ctx);
    assert.equal(f.width, 200); assert.equal(f.height, 100); assert.equal(f.dpr, 2);
    assert.equal(f.dt, 16); assert.ok(f.fps > 0);
  });

  test("onResize fires resize only when device dims change", async () => {
    const sizes = [];
    const factory = canvasGuest({ async setup() { return {}; }, resize(s, c) { sizes.push([c.width, c.height]); }, frame() {} });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 100, h: 80, dpr: 1 }));
    guest.onResize(100, 80, 1); // no change
    guest.onResize(120, 80, 1); // change
    guest.onResize(120, 80, 1); // no change
    assert.deepEqual(sizes, [[100, 80], [120, 80]]); // initial + the one change
  });

  test("fps is a smoothed EMA of 1000/dt", async () => {
    let lastFps = 0;
    const factory = canvasGuest({ async setup() { return {}; }, frame(s, c) { lastFps = c.fps; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
    for (let i = 0; i < 10; i++) guest.frame(20); // 50 fps
    assert.equal(Math.round(lastFps), 50);
  });

  test("onProps and destroy reach the hooks", async () => {
    const seen = { props: null, destroyed: false };
    const factory = canvasGuest({ async setup() { return {}; }, frame() {}, onProps(s, p) { seen.props = p; }, destroy() { seen.destroyed = true; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
    guest.onProps({ x: 9 });
    guest.destroy();
    assert.deepEqual(seen.props, { x: 9 });
    assert.equal(seen.destroyed, true);
  });

  test("a throw in a later hook is caught (console.warn), not propagated", async () => {
    const warns = [];
    const orig = console.warn; console.warn = (...a) => warns.push(a);
    try {
      const factory = canvasGuest({ async setup() { return {}; }, frame() {}, onProps() { throw new Error("boom"); } });
      const guest = await factory(fakeCanvas(), null, fakeHost({ w: 10, h: 10, dpr: 1 }));
      guest.onProps({}); // must NOT throw
      assert.equal(warns.length, 1);
      assert.match(String(warns[0][0]), /onProps threw/);
    } finally { console.warn = orig; }
  });
});
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `node --test js-driver/test/regions/guest-sdk.test.js`
Expected: FAIL — `Cannot find module '../../swiflow-region-guest.js'`.

- [ ] **Step 3: Implement the raster shim** — `js-driver/swiflow-region-guest.js`

```js
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
```

- [ ] **Step 4: Register the test file** — `js-driver/package.json`

In the `"test"` script string, append ` test/regions/guest-sdk.test.js` to the
existing `node --test …` list (keep it on the same line).

- [ ] **Step 5: Run the tests, verify they pass**

Run: `node --test js-driver/test/regions/guest-sdk.test.js`
Expected: PASS (5 tests).
Then: `npm --prefix js-driver test` → the whole suite still passes.

- [ ] **Step 6: Commit**

```bash
git add js-driver/swiflow-region-guest.js js-driver/test/regions/guest-sdk.test.js js-driver/package.json
git commit -m "feat(regions): canvasGuest shim — raster mode + lifecycle + fps"
```

---

# Task 2: `canvasGuest` — grid mode + reflow detection

**Files:**
- Modify: `js-driver/swiflow-region-guest.js`
- Test: `js-driver/test/regions/guest-sdk.test.js`

- [ ] **Step 1: Write the failing tests** — append to `guest-sdk.test.js`

```js
describe("canvasGuest — grid mode", () => {
  function fakeCanvas() { const ctx2d = { _is: "ctx2d" }; return { width: 0, height: 0, getContext: () => ctx2d, _ctx: ctx2d }; }
  function fakeHost(size) { return { emit: () => {}, size }; }

  test("derives cols/rows/cell from cellSize, sizes the buffer, clamps to 8", async () => {
    const got = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { got.push([c.cols, c.rows, c.cell]); }, frame() {} });
    const canvas = fakeCanvas();
    await factory(canvas, null, fakeHost({ w: 200, h: 50, dpr: 1 })); // cols=20, rows=max(8,5)=8
    assert.deepEqual(got, [[20, 8, 10]]);
    assert.equal(canvas.width, 200);  // 20 * 10
    assert.equal(canvas.height, 80);  // 8 * 10
  });

  test("a pure-dpr change keeps the grid: resize skipped, buffer still re-sized", async () => {
    const grids = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { grids.push([c.cols, c.rows, c.cell]); }, frame() {} });
    const canvas = fakeCanvas();
    const guest = await factory(canvas, null, fakeHost({ w: 200, h: 100, dpr: 1 })); // 20x10, cell 10, buffer 200x100
    guest.onResize(400, 200, 2); // same CSS size at dpr 2 → cols 20, rows 10 (unchanged), cell 20
    assert.deepEqual(grids, [[20, 10, 10]]); // only the initial resize
    assert.equal(canvas.width, 400);   // buffer re-sized: 20 * 20
    assert.equal(canvas.height, 200);  // 10 * 20
  });

  test("resize fires when the grid count changes", async () => {
    const grids = [];
    const factory = canvasGuest({ cellSize: 10, async setup() { return {}; }, resize(s, c) { grids.push([c.cols, c.rows]); }, frame() {} });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 200, h: 100, dpr: 1 })); // 20x10
    guest.onResize(300, 100, 1); // 30x10 → change
    assert.deepEqual(grids, [[20, 10], [30, 10]]);
  });

  test("frame forwards cols/rows/cell/dpr", async () => {
    let f = null;
    const factory = canvasGuest({ cellSize: 6, async setup() { return {}; }, frame(s, c) { f = c; } });
    const guest = await factory(fakeCanvas(), null, fakeHost({ w: 120, h: 60, dpr: 1 })); // 20x10, cell 6
    guest.frame(16);
    assert.equal(f.cols, 20); assert.equal(f.rows, 10); assert.equal(f.cell, 6); assert.equal(f.dpr, 1);
    assert.ok(f.ctx2d && f.dt === 16);
  });
});
```

- [ ] **Step 2: Run, verify the new grid tests fail**

Run: `node --test js-driver/test/regions/guest-sdk.test.js`
Expected: the 4 grid tests FAIL (cols/rows/cell are `undefined`; canvas sized to raw
device size, not the grid).

- [ ] **Step 3: Add grid mode to the shim** — replace the body of `guestFactory` in
`js-driver/swiflow-region-guest.js` so `applySize`/`dims`/`frame` branch on a grid
flag. The full file becomes:

```js
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
```

- [ ] **Step 4: Run the full shim suite, verify it passes**

Run: `node --test js-driver/test/regions/guest-sdk.test.js`
Expected: PASS (9 tests — 5 raster + 4 grid). The raster tests still pass (raster
branch unchanged in behaviour).

- [ ] **Step 5: Commit**

```bash
git add js-driver/swiflow-region-guest.js js-driver/test/regions/guest-sdk.test.js
git commit -m "feat(regions): canvasGuest grid mode + reflow detection"
```

---

# Task 3: CLI distribution of `swiflow-region-guest.js`

Threads a new `guestSdkSource` through the embed + scaffold pipeline, mirroring
`regionsSource` exactly. **Do these in order** — the regen (Step 3) depends on the
script + embedder edits.

**Files:** see the per-step paths.

- [ ] **Step 1: Codegen script** — `scripts/embed-driver.swift`

After the `regionsPath` line (`:23`) add:
```swift
let guestSdkPath = cwd.appendingPathComponent("js-driver/swiflow-region-guest.js")
```
Add `guestSdkPath` to the existence-check loop (`:26`): `for path in [jsPath, swPath, regionsPath, guestSdkPath] {`.
Add the read alongside the others (`:33-39`):
```swift
let guestSdk: String
…
    guestSdk = try String(contentsOf: guestSdkPath, encoding: .utf8)
```
In the `output` string, update the `// Source:` line to append ` + js-driver/swiflow-region-guest.js`, and add a fourth constant after `regionsSource` (`:75`):
```swift
    static let guestSdkSource: String = #\"\"\"
\(guestSdk)
\"\"\"#
```

- [ ] **Step 2: Embedder function** — `Sources/SwiflowCLI/DriverEmbedder.swift`

Change the signature (`:19`) to:
```swift
static func swiftSource(driverJS: String, swJS: String, regionsJS: String, guestSdkJS: String) -> String {
```
Update the `// Source:` line to append ` + js-driver/swiflow-region-guest.js`, and
add the fourth constant after `regionsSource` (`:45-47`), matching the indentation:
```swift
    static let guestSdkSource: String = #\"\"\"
\(guestSdkJS)
\"\"\"#
```

- [ ] **Step 3: Regenerate the embedded driver**

Run: `swift scripts/embed-driver.swift`
Expected: `wrote …/EmbeddedDriver.swift (…)`. `git diff Sources/SwiflowCLI/EmbeddedDriver.swift`
shows a new `static let guestSdkSource` block and the updated `// Source:` comment.

- [ ] **Step 4: Scaffold writer** — `Sources/SwiflowCLI/Project/ProjectWriter.swift`

Add `jsGuestSdkSource: String,` to the `writeProject` parameter list (after
`jsRegionsSource:`, `:45`), update the doc comment to mention it, and add a write
after the `jsRegionsSource.write(…)` block (`:92-96`):
```swift
            try jsGuestSdkSource.write(
                to: project.appendingPathComponent("swiflow-region-guest.js"),
                atomically: true,
                encoding: .utf8
            )
```

- [ ] **Step 5: Production call site** — `Sources/SwiflowCLI/Commands/InitCommand.swift`

At the `writeProject(…)` call (`:135` passes `jsRegionsSource: EmbeddedDriver.regionsSource`),
add the line:
```swift
                jsGuestSdkSource: EmbeddedDriver.guestSdkSource
```
(keep argument order: it follows `jsRegionsSource`).

- [ ] **Step 6: Test call sites** — add `jsGuestSdkSource` to every other
`writeProject` caller, and `guestSdkJS` to every `swiftSource` caller:

`writeProject` callers — add after their `jsRegionsSource:` argument:
- `Tests/SwiflowCLITests/DevCommandTests.swift:109` → `jsGuestSdkSource: EmbeddedDriver.guestSdkSource`
- `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift:422` → `jsGuestSdkSource: EmbeddedDriver.guestSdkSource`
- `Tests/SwiflowCLITests/BuildCommandTests.swift:359` and `:411` → `jsGuestSdkSource: EmbeddedDriver.guestSdkSource`
- `Tests/SwiflowCLITests/InitCommandTests.swift:21,50,71,96,119,146,168` (7 calls) →
  `jsGuestSdkSource: "// fake guest sdk\n"`

`swiftSource` callers — `Tests/SwiflowCLITests/DriverEmbedderTests.swift`:
- `:14` add `guestSdkJS: guestSdkJS` (and define a local `let guestSdkJS = "console.log('guest-sdk');"` next to the existing `regionsJS` stub above it).
- `:98` add `guestSdkJS: guestSdkSource` (and read it: `let guestSdkSource = try String(contentsOf: repoRoot.appendingPathComponent("js-driver/swiflow-region-guest.js"), encoding: .utf8)` next to the existing `regionsSource` read).

- [ ] **Step 7: Freshness test** — `Tests/SwiflowCLITests/DriverEmbedderTests.swift`

Mirror the `regionsSourceIsFresh` test (`:52-58`). Add:
```swift
    @Test("EmbeddedDriver.guestSdkSource matches js-driver/swiflow-region-guest.js verbatim")
    func guestSdkSourceIsFresh() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("js-driver/swiflow-region-guest.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(EmbeddedDriver.guestSdkSource == onDisk,
            "EmbeddedDriver.guestSdkSource drifted — re-run `swift scripts/embed-driver.swift`")
    }
```
(Use the exact `repoRoot` derivation already used by `regionsSourceIsFresh`.) Also add
`#expect(generated.contains("static let guestSdkSource: String"))` next to the
existing `regionsSource` contains-check (`:19`).

- [ ] **Step 8: Sync the committed example copy**

Run: `cp js-driver/swiflow-region-guest.js examples/RegionDemo/swiflow-region-guest.js`

- [ ] **Step 9: Run the CLI tests**

Run: `swift test --filter DriverEmbedder` → PASS (incl. the new freshness test).
Run: `swift build` → compiles (confirms every `writeProject`/`swiftSource` call site
was updated; a missed one is a compile error).

- [ ] **Step 10: Commit**

```bash
git add scripts/embed-driver.swift Sources/SwiflowCLI/DriverEmbedder.swift \
        Sources/SwiflowCLI/EmbeddedDriver.swift Sources/SwiflowCLI/Project/ProjectWriter.swift \
        Sources/SwiflowCLI/Commands/InitCommand.swift Tests/SwiflowCLITests/ \
        examples/RegionDemo/swiflow-region-guest.js
git commit -m "feat(cli): embed + scaffold swiflow-region-guest.js"
```

---

# Task 4: Migrate RegionDemo's adapter onto `canvasGuest`

**Files:**
- Modify: `examples/RegionDemo/regions/game-of-life/adapter.js`
- Modify (refocus): `js-driver/test/regions/adapter.test.js`

- [ ] **Step 1: Rewrite the refocused adapter test first** — replace
`js-driver/test/regions/adapter.test.js` with tests against the *hooks* (the draw +
GoL logic that survives the migration). The sizing/reflow/fps assertions are gone —
they now live in `guest-sdk.test.js`.

```js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { hooks, drawCells } from "../../../examples/RegionDemo/regions/game-of-life/adapter.js";

// Oversized buffer so drawCells never reads out of bounds at any grid.
function fakeEx(aliveIndices) {
  const bytes = new Uint8Array(8192);
  for (const i of aliveIndices) bytes[i >> 3] |= (1 << (i & 7));
  let gen = 0; const inits = [];
  return {
    memory: { buffer: bytes.buffer },
    init: (w, h, seed) => inits.push([w, h, seed]),
    cells: () => 0, tick: () => { gen++; }, _gen: () => gen, _inits: inits,
  };
}
function fakeCtx() {
  const rects = [];
  return {
    fillStyle: "", font: "", textBaseline: "",
    fillRect: (x, y, w, h) => rects.push([x, y, w, h]),
    measureText: (s) => ({ width: s.length * 6 }), fillText() {},
    _rects: rects,
  };
}

describe("game-of-life hooks", () => {
  test("drawCells draws a fillRect per live cell at grid coords", () => {
    const ex = fakeEx([0, 23]); // 10x8 grid: 0 → (0,0), 23 → (3,2)
    const ctx2d = fakeCtx();
    drawCells(ctx2d, ex, 10, 8, 10);
    assert.deepEqual(ctx2d._rects.filter((r) => r[2] === 10 && r[3] === 10),
      [[0, 0, 10, 10], [30, 20, 10, 10]]);
  });

  test("resize re-seeds with the current seed and resets the count", () => {
    const ex = fakeEx([]);
    const s = { ex, seed: 7, gen: 99, reseed: false };
    hooks.resize(s, { cols: 12, rows: 9 });
    assert.deepEqual(ex._inits, [[12, 9, 7]]);
    assert.equal(s.gen, 0);
  });

  test("onProps flags a reseed only on a reset-token change", () => {
    const s = { seed: 0, reseed: false };
    hooks.onProps(s, { reset: 0 }); assert.equal(s.reseed, false);
    hooks.onProps(s, { reset: 1 }); assert.equal(s.reseed, true); assert.equal(s.seed, 1);
  });

  test("frame ticks, applies a pending reseed once, emits generation every 64", () => {
    const ex = fakeEx([]);
    const emits = [];
    const s = { ex, seed: 2, gen: 0, reseed: true };
    const ctx = { ctx2d: fakeCtx(), cols: 8, rows: 8, cell: 6, dpr: 1, fps: 60, emit: (e) => emits.push(e) };
    for (let i = 0; i < 64; i++) hooks.frame(s, ctx);
    assert.deepEqual(ex._inits, [[8, 8, 2]]); // reseed applied once, on the first frame
    assert.equal(s.gen, 64);
    assert.deepEqual(emits.at(-1), { kind: "generation", value: 64 });
  });
});
```

- [ ] **Step 2: Run, verify it fails**

Run: `node --test js-driver/test/regions/adapter.test.js`
Expected: FAIL — the adapter doesn't export `hooks`/`drawCells` yet (old export was
`makeGuest`).

- [ ] **Step 3: Rewrite the adapter onto `canvasGuest`** — replace
`examples/RegionDemo/regions/game-of-life/adapter.js`:

```js
// Hosts our AssemblyScript Game-of-Life guest (./universe.ts -> ./universe.wasm)
// via the canvasGuest SDK: the shim owns the canvas, dpr-crisp grid sizing, reflow,
// fps, and lifecycle; here we write only the load + the per-frame tick/draw.
import { canvasGuest } from "../../swiflow-region-guest.js";

async function loadUniverse() {
  const res = await fetch(new URL("./universe.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(),
    { env: { abort: () => { throw new Error("AssemblyScript abort()"); } } });
  return instance.exports;
}

// Pure draw helpers (the only thing the shim can't own). Exported for unit tests.
export function drawCells(ctx2d, ex, cols, rows, cell) {
  const cells = new Uint8Array(ex.memory.buffer, ex.cells() >>> 0, Math.ceil((cols * rows) / 8));
  ctx2d.fillStyle = "#fff";
  ctx2d.fillRect(0, 0, cols * cell, rows * cell);
  ctx2d.fillStyle = "#111";
  for (let i = 0; i < cols * rows; i++) {
    if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % cols) * cell, ((i / cols) | 0) * cell, cell, cell);
  }
}

export function drawFps(ctx2d, fps, dpr) {
  const label = `${Math.round(fps)} fps`;
  const fontPx = Math.round(13 * dpr);
  ctx2d.font = `${fontPx}px system-ui, sans-serif`;
  ctx2d.textBaseline = "top";
  const padX = Math.round(fontPx * 0.5), padY = Math.round(fontPx * 0.35);
  const tw = ctx2d.measureText(label).width;
  ctx2d.fillStyle = "rgba(17,17,17,0.7)";
  ctx2d.fillRect(0, 0, tw + padX * 2, fontPx + padY * 2);
  ctx2d.fillStyle = "#fff";
  ctx2d.fillText(label, padX, padY);
}

// The guest hooks. Exported so the GoL logic is unit-tested directly.
export const hooks = {
  cellSize: 6,
  async setup() { return { ex: await loadUniverse(), seed: 0, gen: 0, reseed: false }; },
  resize(s, { cols, rows }) { s.ex.init(cols, rows, s.seed); s.gen = 0; },
  onProps(s, p) { if (p && p.reset !== s.seed) { s.seed = p.reset; s.reseed = true; } },
  frame(s, { ctx2d, cols, rows, cell, dpr, fps, emit }) {
    if (s.reseed) { s.ex.init(cols, rows, s.seed); s.gen = 0; s.reseed = false; }
    s.ex.tick(); s.gen++;
    drawCells(ctx2d, s.ex, cols, rows, cell);
    drawFps(ctx2d, fps, dpr);
    if (s.gen % 64 === 0) emit({ kind: "generation", value: s.gen });
  },
};

export default canvasGuest(hooks);
```

- [ ] **Step 4: Run the JS suites, verify they pass**

Run: `node --test js-driver/test/regions/adapter.test.js` → PASS (4 tests).
Run: `npm --prefix js-driver test` → whole suite green (guest-sdk + adapter +
universe-wasm + the rest).

- [ ] **Step 5: Browser e2e (unchanged spec, must still round-trip)**

The worker imports `swiflow-region-guest.js` from the app root; `swiflow dev` serves
the committed copy (synced in Task 3). Build the release CLI first (the harness reuses
it) and run the one suite:

```bash
swift build -c release --product swiflow
npm --prefix Tests/playwright run test:regions
```
Expected: 1 passed — the rewritten adapter boots, the canvas mounts, the generation
counter climbs, zero console errors.

- [ ] **Step 6: Commit**

```bash
git add examples/RegionDemo/regions/game-of-life/adapter.js js-driver/test/regions/adapter.test.js
git commit -m "refactor(regions): migrate RegionDemo's adapter onto canvasGuest"
```

---

## Exit criteria

- `canvasGuest` exists, raster + grid, unit-tested (`guest-sdk.test.js`, 9 tests).
- It's embedded + scaffolded like `swiflow-regions.js` (`guestSdkSource`, freshness
  test, `swiflow init` writes `swiflow-region-guest.js`).
- RegionDemo's adapter is ~30 lines of pure Game-of-Life on the shim; its remaining
  logic is unit-tested via the exported `hooks`/`drawCells`; the browser e2e still
  passes.
- Full suites green: `npm --prefix js-driver test`, `swift test --filter DriverEmbedder`,
  `npm --prefix Tests/playwright run test:regions`.

## Out of scope (future layers, per the spec)

`swiflow region <Name>` scaffold generator; the Rust `#[region]` proc-macro + crate;
AssemblyScript/C/Zig guest SDKs; a `webglGuest` convenience.
