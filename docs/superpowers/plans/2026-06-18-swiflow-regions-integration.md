# Swiflow Regions — Browser Integration Implementation Plan (Plan 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make Swiflow Regions run end-to-end in a real browser, proving the polyglot promise by hosting an off-the-shelf compiled-wasm guest we didn't write (`rustwasm/wasm_game_of_life`) — and make the runtime shippable through `swiflow init`.

**Architecture:** A self-contained `examples/RegionDemo` (built in-place by `swiflow dev`, exactly like `examples/EdgeCases`) renders `region(GameOfLife.self, …)`. The guest is the **Game-of-Life Rust/wasm `Universe`** (DOM-free pure compute) plus a ~30-line JS **adapter** that ticks it and draws the cell bitmap to the OffscreenCanvas. A Playwright spec drives it on its own port. Separately, the CLI is taught to embed + scaffold `swiflow-regions.js` so any `swiflow init` app loads the runtime.

**Tech Stack:** the Plan 2 runtime (`js-driver/swiflow-regions.js`), `swiflow dev` in-place serving (`HTTPRouter` `GET /**`, `.wasm`→`application/wasm`), Playwright (`Tests/playwright/`), the embed pipeline (`scripts/embed-driver.swift` + `DriverEmbedder` + `ProjectWriter`).

**Depends on:** Plan 1 (core, on `main`) + Plan 2 (the runtime, PR #41). Execute on a branch off `feat/swiflow-regions-runtime` (or off `main` after #41 merges).

## ⚠️ External prerequisite (no Rust toolchain in this environment)

**Task A2 (vendor the Game-of-Life artifact) requires `wasm-pack`/`cargo`, which are not installed here.** A human or a Rust-capable CI job must produce the artifact once and commit it; until then, the **browser e2e (Task A4) is gated** and will be skipped/red. Everything else (the adapter + its unit test, the RegionDemo Swift app, the CLI embed/scaffold) is executable now. If producing the artifact proves impractical, the documented fallback is an **AssemblyScript guest** (npm `asc`, no Rust) — swap it in for A2 and point the adapter/spec at it; the rest of the plan is unchanged.

---

## File Structure

**Created:**
- `examples/RegionDemo/` — `Package.swift`, `Sources/App/App.swift`, `index.html`, committed `swiflow-driver.js`/`swiflow-sw.js`/`swiflow-regions.js`, and `regions/game-of-life/{adapter.js, wasm_game_of_life.js, wasm_game_of_life_bg.wasm}`.
- `js-driver/test/regions/adapter.test.js` — unit test for the adapter's pure logic (no real wasm).
- `Tests/playwright/region.spec.ts` — the browser e2e.

**Modified (Phase A):**
- `Tests/playwright/playwright.config.ts` — add a 5th in-place `webServer` (`:3004`).
- `.gitignore` — ensure `examples/RegionDemo/.build` is ignored (matches other examples).

**Modified (Phase B — CLI distribution):**
- `scripts/embed-driver.swift`, `Sources/SwiflowCLI/DriverEmbedder.swift`, `Sources/SwiflowCLI/EmbeddedDriver.swift` — add `regionsSource`.
- `Sources/SwiflowCLI/Project/ProjectWriter.swift` — write `swiflow-regions.js`.
- `Sources/SwiflowCLI/EmbeddedTemplates.swift` (via examples/*/index.html + regen) — add the `<script type="module">`.
- `Tests/SwiflowCLITests/DriverEmbedderTests.swift` — `regionsSource` freshness test.

---

# Phase A — RegionDemo + the Game-of-Life guest + the e2e

## Task A1: The Game-of-Life adapter (with a unit-testable core)

**Files:**
- Create: `examples/RegionDemo/regions/game-of-life/adapter.js`
- Test: `js-driver/test/regions/adapter.test.js`

The adapter conforms to the guest contract (default export `(canvas, props, ctx) => guest`). Its wasm-import glue is thin (e2e-verified); its **drawing + tick/emit logic is extracted into a pure, injected core** so it's unit-testable here without the real wasm.

- [ ] **Step 1: Write the failing test**

```javascript
// js-driver/test/regions/adapter.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { makeGuest } from "../../../examples/RegionDemo/regions/game-of-life/adapter.js";

// A fake "Universe" + memory standing in for the wasm-pack module.
function fakeUniverse(w, h, aliveIndices) {
  // bit-packed cells (the wasm_game_of_life "exercise" layout): 1 bit per cell.
  const bytes = new Uint8Array(Math.ceil((w * h) / 8));
  for (const i of aliveIndices) bytes[i >> 3] |= (1 << (i & 7));
  let gen = 0;
  return {
    memory: { buffer: bytes.buffer },
    universe: {
      width: () => w, height: () => h, cells: () => 0, // ptr 0 into our buffer
      tick: () => { gen++; }, free: () => {},
      _gen: () => gen,
    },
  };
}

// A fake 2D context that records fillRect calls.
function fakeCtx() {
  const rects = [];
  return { fillStyle: "", fillRect: (x, y, w, h) => rects.push([x, y, w, h]), _rects: rects };
}

describe("game-of-life adapter core", () => {
  test("draws a fillRect per live cell at the right grid coords", () => {
    const { memory, universe } = fakeUniverse(3, 2, [0, 5]); // cell 0 and cell 5 alive
    const ctx2d = fakeCtx();
    const guest = makeGuest({
      wasmMemory: memory, universe, ctx2d,
      width: 3, height: 2, cell: 10,
      emit: () => {},
    });
    guest.frame();
    // cell 0 -> (0,0); cell 5 -> col 2,row 1 -> (20,10); each 10x10
    assert.deepEqual(ctx2d._rects.filter((r) => r[2] === 10 && r[3] === 10),
      [[0, 0, 10, 10], [20, 10, 10, 10]]);
  });

  test("ticks `speed` times per frame and emits a generation event periodically", () => {
    const { memory, universe } = fakeUniverse(2, 2, []);
    let emitted = null;
    const guest = makeGuest({
      wasmMemory: memory, universe, ctx2d: fakeCtx(),
      width: 2, height: 2, cell: 4, speed: 64, emit: (e) => { emitted = e; },
    });
    guest.frame();
    assert.equal(universe._gen(), 64);
    assert.deepEqual(emitted, { kind: "generation", value: 64 });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd js-driver && node --test test/regions/adapter.test.js`
Expected: FAIL — adapter / `makeGuest` not found.

- [ ] **Step 3: Implement the adapter**

```javascript
// examples/RegionDemo/regions/game-of-life/adapter.js
//
// Hosts the EXTERNAL rustwasm/wasm_game_of_life module unmodified: its `Universe`
// is DOM-free pure compute, so it runs in our Web Worker. This adapter ticks it
// and blits the cell bitmap to the OffscreenCanvas. Provenance of the vendored
// wasm: see ./PROVENANCE.md.

// Pure, injected core — unit-tested without the real wasm.
export function makeGuest({ wasmMemory, universe, ctx2d, width, height, cell, speed = 1, emit }) {
  let gen = 0;
  let rate = speed;
  function draw() {
    const cells = new Uint8Array(wasmMemory.buffer, universe.cells(), Math.ceil((width * height) / 8));
    ctx2d.fillStyle = "#fff";
    ctx2d.fillRect(0, 0, width * cell, height * cell);
    ctx2d.fillStyle = "#111";
    for (let i = 0; i < width * height; i++) {
      if ((cells[i >> 3] >> (i & 7)) & 1) ctx2d.fillRect((i % width) * cell, ((i / width) | 0) * cell, cell, cell);
    }
  }
  return {
    onProps(p) { if (p && p.speed != null) rate = p.speed; },
    frame() {
      for (let i = 0; i < rate; i++) { universe.tick(); gen++; }
      draw();
      if (gen % 64 === 0) emit({ kind: "generation", value: gen });
    },
    destroy() { universe.free?.(); },
  };
}

// The guest factory the worker calls. Imports the EXTERNAL wasm module and wires
// it to makeGuest. (Exercised by the browser e2e; the wasm import can't run in node.)
export default async function gameOfLife(canvas, props, ctx) {
  const mod = await import("./wasm_game_of_life.js");
  const wasm = await mod.default();         // wasm-pack --target web: default export is init()
  const universe = mod.Universe.new();
  const width = universe.width(), height = universe.height();
  const cell = (props && props.cellSize) || 6;
  canvas.width = width * cell;
  canvas.height = height * cell;
  return makeGuest({
    wasmMemory: wasm.memory, universe, ctx2d: canvas.getContext("2d"),
    width, height, cell, speed: (props && props.speed) || 1, emit: ctx.emit,
  });
}
```

- [ ] **Step 4: Run to verify it passes + wire into the suite**

Run: `cd js-driver && node --test test/regions/adapter.test.js` → PASS.
Append the file to `js-driver/package.json`'s `test` script; `npm test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/RegionDemo/regions/game-of-life/adapter.js js-driver/test/regions/adapter.test.js js-driver/package.json
git commit -m "feat(regions): Game-of-Life guest adapter (testable draw/tick core)"
```

---

## Task A2: ⚠️ Vendor the Game-of-Life wasm artifact (REQUIRES wasm-pack — external step)

**Files:**
- Create: `examples/RegionDemo/regions/game-of-life/wasm_game_of_life.js` + `wasm_game_of_life_bg.wasm` (built artifacts, checked in)
- Create: `examples/RegionDemo/regions/game-of-life/PROVENANCE.md`

- [ ] **Step 1: Produce the artifact (on a Rust-capable machine)**

```bash
git clone https://github.com/rustwasm/wasm_game_of_life /tmp/gol
cd /tmp/gol
# Pin the commit you build (record it in PROVENANCE.md).
wasm-pack build --target web --out-dir pkg
# Copy the two files the adapter imports:
cp pkg/wasm_game_of_life.js        <repo>/examples/RegionDemo/regions/game-of-life/
cp pkg/wasm_game_of_life_bg.wasm   <repo>/examples/RegionDemo/regions/game-of-life/
```

- [ ] **Step 2: Confirm the exported API matches the adapter**

The adapter assumes wasm-pack `--target web` shape: the module's **default export is `init()`** (returns the instance exposing `.memory`) and it exports **`Universe`** with `new()/width()/height()/cells()/tick()/free()`. If the pinned commit differs (e.g. a `Cell`-enum byte layout instead of bit-packed `cells()`), adjust `adapter.js`'s `draw()` bit math accordingly and update the `adapter.test.js` fixture to match. Record the exact API + commit in `PROVENANCE.md`.

- [ ] **Step 3: Write PROVENANCE.md**

```markdown
# Game-of-Life guest — provenance
- Source: https://github.com/rustwasm/wasm_game_of_life @ <commit-sha>
- Built with: wasm-pack <version>, `wasm-pack build --target web`
- Files: wasm_game_of_life.js (glue), wasm_game_of_life_bg.wasm (module)
- Cell layout: bit-packed (1 bit/cell) via `Universe.cells()` — see adapter.js draw().
- License: <upstream license> (MIT/Apache-2.0) — retained here as a vendored dependency.
```

- [ ] **Step 4: Commit**

```bash
git add examples/RegionDemo/regions/game-of-life/wasm_game_of_life.js \
        examples/RegionDemo/regions/game-of-life/wasm_game_of_life_bg.wasm \
        examples/RegionDemo/regions/game-of-life/PROVENANCE.md
git commit -m "chore(regions): vendor rustwasm/wasm_game_of_life guest artifact"
```

**If you cannot run wasm-pack:** stop here and report BLOCKED on A2 (and therefore A4). Do A1, A3, and Phase B, then hand A2 back to a Rust-capable human/CI. (Or switch to the AssemblyScript fallback noted at the top.)

---

## Task A3: The RegionDemo example (Swift app + page)

**Files:**
- Create: `examples/RegionDemo/Package.swift`, `Sources/App/App.swift`, `index.html`
- Copy: `swiflow-driver.js`, `swiflow-sw.js`, `swiflow-regions.js` from `js-driver/` into `examples/RegionDemo/`

- [ ] **Step 1: `Package.swift`** (mirrors `examples/MiniRouter/Package.swift`)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RegionDemo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "App", targets: ["App"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
```

- [ ] **Step 2: `Sources/App/App.swift`**

```swift
import Swiflow
import SwiflowDOM
import JavaScriptKit

struct GoLProps: Encodable { var speed: Int; var cellSize: Int }
struct GoLEvent: RegionEvent { let kind: String; let value: Int }
enum GameOfLife: RegionGuest {
    typealias Props = GoLProps
    typealias Event = GoLEvent
    static let source = "regions/game-of-life/adapter.js"
}

final class Demo: Component {
    @State var generation = 0
    @State var failed = false

    var body: VNode {
        div {
            h1("Swiflow Regions — Game of Life")
            // The generation counter is driven by guest-emitted events: proof the
            // round-trip (guest wasm → worker → sf:event → @State) works.
            p("Generation: \(generation)")
            if failed {
                p("⚠️ guest failed to load").class("error")
            } else {
                region(GameOfLife.self, key: "gol", props: GoLProps(speed: 1, cellSize: 6))
                    .onEvent { e in generation = e.value }      // e: GoLEvent inferred
                    .onError { _ in failed = true }              // sibling fallback
                    .frame(width: 360, height: 360)
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() { Swiflow.render(into: "#app") { Demo() } }
}
```

(Match the real `Component`/`@State` API as used in `examples/MiniRouter/Sources/App` — adjust the declaration form if the example pattern differs, e.g. a `struct` conforming to `Component`.)

- [ ] **Step 3: `index.html`** (HelloWorld's, plus the regions module script)

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>RegionDemo</title>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
    <script type="module" src="swiflow-regions.js"></script>
  </body>
</html>
```

- [ ] **Step 4: Copy the JS runtime files in**

```bash
cp js-driver/swiflow-driver.js js-driver/swiflow-sw.js js-driver/swiflow-regions.js examples/RegionDemo/
```

- [ ] **Step 5: Build it (proves the Swift app + the region API compile to wasm)**

Run: `swift build -c release --product swiflow && .build/release/swiflow build --path examples/RegionDemo`
Expected: a successful build producing the wasm under `examples/RegionDemo/.build/...`. (This is the canonical "does the demo compile + bundle" check; per repo convention, build the release CLI first.)

- [ ] **Step 6: Commit**

```bash
echo ".build/" > examples/RegionDemo/.gitignore
git add examples/RegionDemo/Package.swift examples/RegionDemo/Sources examples/RegionDemo/index.html \
        examples/RegionDemo/swiflow-driver.js examples/RegionDemo/swiflow-sw.js examples/RegionDemo/swiflow-regions.js \
        examples/RegionDemo/.gitignore
git commit -m "feat(regions): RegionDemo example hosting the Game-of-Life guest"
```

---

## Task A4: The Playwright e2e (gated on A2)

**Files:**
- Modify: `Tests/playwright/playwright.config.ts` (add the `:3004` in-place server)
- Create: `Tests/playwright/region.spec.ts`

- [ ] **Step 1: Add the webServer entry** (mirror the EdgeCases `:3003` in-place pattern)

In `Tests/playwright/playwright.config.ts`, add a `REGION_DIR = join(REPO_ROOT, "examples", "RegionDemo")` const and append to the `webServer` array:

```typescript
    {
      command: `'${SWIFLOW}' dev --path '${REGION_DIR}' --port 3004`,
      url: "http://127.0.0.1:3004",
      reuseExistingServer: false,
      timeout: 300_000,
    },
```

- [ ] **Step 2: Write the spec**

```typescript
// Tests/playwright/region.spec.ts
import { test, expect, type ConsoleMessage } from "@playwright/test";

test.describe("Regions — Game of Life guest", () => {
  test.use({ baseURL: "http://127.0.0.1:3004" });

  test("the guest boots, advances, and round-trips events to @State", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m); });

    await page.goto("/");
    await expect(page.getByRole("heading", { name: /Game of Life/ })).toBeVisible();

    // generation starts at 0, then climbs as the guest emits `generation` events.
    await expect(page.getByText("Generation: 0")).toBeVisible();
    await expect(page.getByText(/Generation: (6[4-9]|[1-9]\d{2,})/)).toBeVisible({ timeout: 15_000 });

    // the <sf-region> mounted a canvas, and nothing errored.
    await expect(page.locator("sf-region canvas")).toBeVisible();
    expect(errors.map((e) => e.text()), "no console errors").toHaveLength(0);
  });
});
```

- [ ] **Step 3: Run the suite locally (requires A2's artifact + the release CLI)**

Run: `swift build -c release --product swiflow && cd Tests/playwright && npx playwright test region.spec.ts`
Expected: PASS. **If A2's artifact is missing, this is BLOCKED** — the guest module 404s and the generation never climbs. Report BLOCKED on A4 pending A2 rather than weakening the assertions.

- [ ] **Step 4: Commit**

```bash
git add Tests/playwright/playwright.config.ts Tests/playwright/region.spec.ts
git commit -m "test(regions): Playwright e2e for the Game-of-Life region"
```

---

# Phase B — Ship the runtime through `swiflow init` (so every app can use regions)

> Phase A proves Regions work; Phase B makes them usable in any scaffolded project (not just the in-place RegionDemo). Independent of A — can be done before or after.

## Task B1: Embed `swiflow-regions.js` into the CLI + write it on scaffold

**Files:**
- Modify: `scripts/embed-driver.swift`, `Sources/SwiflowCLI/DriverEmbedder.swift`, `Sources/SwiflowCLI/EmbeddedDriver.swift` (regenerated), `Sources/SwiflowCLI/Project/ProjectWriter.swift`
- Test: `Tests/SwiflowCLITests/DriverEmbedderTests.swift`

- [ ] **Step 1: Add `regionsSource` to the embedder.** In `DriverEmbedder.swiftSource(driverJS:swJS:)`, add a `regionsJS:` parameter and emit a third constant:

```swift
    static let regionsSource: String = #"""
\#(regionsJS)
"""#
```

(Follow the exact `\n`-stripping raw-string pattern the file documents for the other two.) Update `scripts/embed-driver.swift` to also read `js-driver/swiflow-regions.js` and pass it through; update the `output` literal identically.

- [ ] **Step 2: Add the freshness test** in `DriverEmbedderTests.swift`, mirroring `embeddedDriverIsFresh`:

```swift
    @Test("EmbeddedDriver.regionsSource matches js-driver/swiflow-regions.js verbatim")
    func regionsSourceIsFresh() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("js-driver/swiflow-regions.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(EmbeddedDriver.regionsSource == onDisk,
                "Run `swift scripts/embed-driver.swift` to regenerate EmbeddedDriver.swift")
    }
```

- [ ] **Step 3: Run the codegen + the test (RED→GREEN ordering).**

`swift test --filter 'SwiflowCLITests.DriverEmbedderTests/regionsSourceIsFresh'` → FAIL (no `regionsSource`). Then `swift scripts/embed-driver.swift` to regenerate, and re-run → PASS. Also confirm `DriverEmbedderTests` still has the script-vs-library-output match (the script and `DriverEmbedder.swiftSource` must produce identical bytes).

- [ ] **Step 4: Write `swiflow-regions.js` on scaffold.** In `ProjectWriter.writeProject(...)`, add a `jsRegionsSource:` parameter and write it next to the driver:

```swift
            try jsRegionsSource.write(
                to: project.appendingPathComponent("swiflow-regions.js"),
                atomically: true, encoding: .utf8
            )
```

Thread `EmbeddedDriver.regionsSource` through `InitCommand.run()`'s `ProjectWriter.writeProject(...)` call.

- [ ] **Step 5: Commit**

```bash
git add scripts/embed-driver.swift Sources/SwiflowCLI/DriverEmbedder.swift Sources/SwiflowCLI/EmbeddedDriver.swift \
        Sources/SwiflowCLI/Project/ProjectWriter.swift Tests/SwiflowCLITests/DriverEmbedderTests.swift
git commit -m "feat(cli): embed + scaffold swiflow-regions.js"
```

## Task B2: Add the regions `<script>` to the default template

**Files:**
- Modify: `examples/*/index.html` (the template source) + regenerate `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Add the module script** after `<script src="swiflow-driver.js"></script>` in the relevant template index.html(s) under `examples/`:

```html
    <script type="module" src="swiflow-regions.js"></script>
```

- [ ] **Step 2: Regenerate the embedded templates** (the repo's `examples/`→`EmbeddedTemplates` codegen — the same step the memory note "examples/ changes need embed-templates regen" refers to; find the script under `scripts/` and run it), then run the template byte-equality tests:

Run: `swift test --filter 'SwiflowCLITests.TemplatesTests'`
Expected: PASS after regen. (If a scaffold-output test asserts index.html contents, update its expectation to include the new script.)

- [ ] **Step 3: Commit**

```bash
git add examples/*/index.html Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "feat(cli): scaffolded apps load the regions runtime"
```

---

## Exit criteria

- `examples/RegionDemo` builds (`swiflow build --path examples/RegionDemo`) and, served by `swiflow dev`, renders a Game-of-Life canvas whose **generation counter climbs** (guest-emitted `sf:event` → `@State`), with the canvas inside `<sf-region>` and zero console errors — verified by `region.spec.ts` (gated on the A2 artifact).
- The adapter's draw/tick/emit core is unit-tested in `node:test` (no real wasm needed).
- A bad `data-source` dispatches `sf:error` → the sibling fallback renders (can be added as a second spec case).
- `swiflow init <name>` produces a project containing `swiflow-regions.js` and an index.html that loads it (Phase B); `DriverEmbedder` freshness + template byte-equality gates pass.

## Open questions for the implementer

- **GoL API shape:** the adapter assumes wasm-pack `--target web` (default export `init()`, exported `Universe`, bit-packed `cells()`). Confirm against the pinned build in A2; adjust `draw()` + the test fixture if the chosen commit differs.
- **Phase B `<script>` scope:** adding the module to *every* scaffolded app is ~8 KB and self-registering-but-inert. If you'd rather keep non-region apps lean, gate it behind a `--with-regions` init flag or a RegionDemo-only template instead — but the default-on path is simplest and the cost is negligible against the wasm bundle.
- **HMR survival** (Plan 1's keyed diff keeps the worker across a save) is worth a third spec case once the e2e is unblocked.
