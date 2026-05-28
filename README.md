# Swiflow

Frontend ecosystem for Swift on the web: components, virtual DOM, hot-reloading
dev server, WASM output.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

## Current State

Swiflow is **pre-1.0**. The DX uplift plan
([master plan](docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md))
drives the roadmap to 1.0 across phases 6 through 13.

**Status:** Phase 17 (Lifecycle + DOM Sync) — closes two latent
bugs the Playwright router suite exposed: nested-component
`onAppear` now fires (was root-only since the hook was introduced,
which silently broke `Link`'s click handler), and the diff now
emits the `removeChild` / `appendChild` patches needed to keep the
DOM in sync when a component swaps element types between frames
(a new `replaceMount` opcode handles the root-level case). All 3
router.spec.ts e2e tests pass. Phase 16 (Foundation-Free Runtime)
shipped just before: runtime modules no longer import Foundation;
a CI grep guard enforces it. Phase 15's bundle headline still
holds — **1.81 MB gzipped** (−90% vs the pre-15 baseline). User-
facing API essentially unchanged across all three; `@State` still
requires an explicit type annotation as of 15.

**What works today (Phase 17):**
- **HMR** — `swiflow dev` does a state-preserving WASM hot swap on
  every save. `@State` survives, the page doesn't reload, and
  the JS driver logs `[swiflow] hmr-swap took Xms` per swap. The
  centerpiece of Phase 8.
- Reactive Components with `@State` and the typed `Event` DSL —
  `.on(.click) { self.count += 1 }`.
- Two-way bindings — `.value($text)` (String/Int/Double), `.checked($flag)`,
  `.selection($choice)` — on input, textarea, and select.
- `Ref<Element>` for first-party DOM access (focus, scroll, etc.).
- `URLSanitizer`-protected DSL fold (XSS-safe by default).
- `swiflow init` scaffold + `swiflow build` (WASM SDK auto-probe) +
  `swiflow dev` (file-watch + state-preserving HMR).
- **CSS-in-Swift** — `css { }` builder, `rule()`, `keyframes()`, `from {}`,
  `to {}`, `at(_ percent:) {}`, ~50 CSS property functions.
- **Scoped styles** — `static var scopedStyles: CSSSheet?` on any `Component`;
  injected as a `<style>` tag and class-scoped at mount.
- **Exit animations** — `static var exitAnimation: String?` + `exitDuration`;
  the driver plays the animation before DOM removal.
- **`@Component` macro** — components declared with `@MainActor @Component final class Foo { ... }` automatically conform to `Component`. The macro removes the `: Component` boilerplate; the `@MainActor` is still required (Swift 6 doesn't propagate actor isolation retroactively through a macro-emitted conformance extension, so the class body needs its own isolation). `@ChildrenBuilder` emits actionable diagnostics guiding scalar types to the `text(…)` free function.
- **`@Environment` / context DI** — typed `EnvironmentKey` protocol, `EnvironmentValues`, `Environment` property wrapper, plus both the `withEnvironment(\.key, value) { ... }` DSL and the postfix `.environment(\.key, value)` VNode modifier. `EnvironmentValues: Equatable` so the VNode diff detects environment changes.
- **`SwiflowRouter`** — hash- and history-mode routing. `RouterRoot { Route("/") { Home() }; Route("/users/:id") { ctx in User(id: ctx.params["id"]) } }`. `@Environment(\.router)` exposes `path`, `navigate`, `replace`, `back`. Verified end-to-end by Playwright (`router.spec.ts`, 3/3 passing); `Link`'s click handler attaches reliably now that nested components actually receive `onAppear`.
- **Lifecycle hooks across the whole tree** — `onAppear`, `onChange`, `onDisappear` fire on every component in the mount tree, not just the root. Children-first ordering on mount (matches React's `componentDidMount` and SwiftUI's `.onAppear`) so a parent's hook sees its subtree fully mounted; parent-first on unmount so a parent can still read child state during teardown.
- **Form validation** — `FormController`, `Field`, `Form` coordinator with blur-triggered errors, `touchAll()`, `reset()`, `isValid`.
- **`SwiflowTesting`** — headless test harness: `render()`, `find()`, `findAll()`, `click()`, `input()`, `blur()`. See [testing guide](docs/guides/testing.md).
- **Multi-root mount** — `Swiflow.render(into: selector) { ... }` works for multiple selectors; `Swiflow.unmount(into: selector)` for clean teardown.
- 548 Swift tests across 108 suites + 32 JS driver tests (`node --test` against jsdom, covering driver + service worker) + Playwright e2e (Counter + RouterDemo). Guides: [DWARF debugging](docs/guides/debugging.md), [forms](docs/guides/forms.md), [router](docs/guides/router.md), [testing](docs/guides/testing.md).

### Chrome DevTools panel

A read-only Chrome DevTools extension at [`devtools/`](devtools/) shows
the live component tree and `@State` of any Swiflow app running in dev
mode. Sideload via `chrome://extensions` → **Load unpacked** →
select `devtools/`. See [`devtools/README.md`](devtools/README.md) for
the full smoke checklist.

**What's not in the box yet:**
- **`AsyncTestRenderer`** — for `task {}` lifecycle hooks (pre-1.0 follow-up).
- **Lazy components, advanced macro features** — Phase 13+ (partial; `@Component` and `@ChildrenBuilder` diagnostics shipped in 13d).
- **Homebrew distribution** — not packaged yet. The CLI is installable today by cloning + `swift build -c release --product swiflow`; a Homebrew formula is a pre-1.0 polish item. Versioned GitHub releases (tags + release notes) ship with the framework as of 0.1.3.

**Costs you should know:**
- **WASM bundle (HelloWorld example, release):** ~5 MB raw / **~1.8 MB
  gzipped** on the wire on the first visit (Phase 15 redesign shrank
  it 10× from the Phase 14b baseline). First-visit users see a
  `[data-swiflow-progress]` percent during the download (Phase 14b
  Track 3). Order-of-magnitude smaller than the previous Swift-on-WASM
  baseline; comparable to a modest React app. Exact numbers in
  [`docs/perf/bundle-baseline.json`](docs/perf/bundle-baseline.json); every
  PR runs `scripts/measure-bundle.sh` in CI and comments the diff. A >5%
  growth fails the build unless the PR carries the `bundle-size-skip` label.
- **Repeat visits:** ~0 bytes. The service worker shipped in Phase 14b
  caches the WASM and JS runtime by content hash, so visit #2 onward
  serves from local cache until you rebuild. Auto-registers on release
  builds; `swiflow dev` skips it so HMR isn't fighting a stale cache.
- **Cold build:** ~80s (`swift package clean` then
  `swift package --swift-sdk <wasm-sdk> js -c release` from the
  example project).
- **Hot rebuild (single source touched):** ~8s WASM rebuild → HMR swap
  (state preserved). Pre-Phase-8 this was a ~8s rebuild → full page
  reload, with `@State` lost. The 8s rebuild is the same; what changed
  is what happens *after* the rebuild lands. Specific HMR swap times
  recorded in `docs/perf/2026-05-20-hmr-baseline.md`.

Measurements taken on macOS 26.5 / Apple M1 Max with Swift 6.3 / WASM SDK 6.3.
Run the same commands locally to calibrate for your hardware.

**Status:** Phase 17 (Lifecycle + DOM Sync Fixes) complete — two latent
bugs the Playwright router suite finally exposed. First, `onAppear` fired
only on the root component since the hook was introduced (`2601ad9`, well
before the router demo's e2e was added). The mount-time walker now mirrors
the existing destroy walker, firing `onAppear` children-first on every
component anchor. Second, the diff's component-reuse and env-override
update arms left the DOM out of sync on type swaps: destroy emitted
`destroyNode` (handle-map cleanup only) without `removeChild`, and mount
created the new subtree without a parent-level `appendChild`. Both arms
now splice `removeChild` / `appendChild` patches around the recursive
update using a new `domAncestorHandle(_:)` walker; when the swap is at
the root (anchors all the way up), the Renderer instead emits a new
`replaceMount(selector, newHandle)` patch — the JS driver tracks roots
per-selector by Node reference (not handle) so the swap survives the
preceding `destroyNode`. All 3 `router.spec.ts` e2e tests pass.
Phase 16 (Foundation-Free Runtime) complete — `Sources/SwiflowRouter/Core/RouteMatching.swift`
dropped `import Foundation` (queries are decoded by a stdlib
`Unicode.UTF8.ForwardParser`-backed `percentDecode`),
`Sources/SwiflowWeb/HMR/HMRBridge.swift` dropped its vestigial Foundation
import, and a `Verify Foundation-free runtime` step in `.github/workflows/ci.yml`
greps for `^import Foundation$` in the three runtime modules and fails
fast on any hit (runs before the cache restore). Bundle delta was within
noise (Phase 15 already drained Foundation's transitive cost); the win is
architecture hygiene — `grep -rn '^import Foundation' Sources/Swiflow*`
now returns zero, and the 1.0 story is structurally true rather than
aspirational.
Phase 15 (Pre-1.0 Dependency Diet) complete — @State is now a Swift
attached macro; the framework iterates macro-emitted
`_ComponentRuntime.stateCells` instead of walking `Mirror.children`;
release builds compile with `-Xswiftc -disable-reflection-metadata`.
Bundle gzipped 18.17 MB → 1.81 MB. Full audit in
`docs/perf/2026-05-26-wasm-bundle-audit.md`. Phase 14b Track 3
(Progress UI) complete — driver pre-fetches App.wasm via fetchWithProgress and writes the percent to documentElement.dataset.swiflowProgress; new scaffolds ship a default 'Loading N%' overlay users can restyle or delete. Phase 14b Track 2 (WASM Trim — measurement) complete — release builds now use `-Osize -gnone` (0.21% gzipped savings); `wasm-opt -Oz` post-processing and `wasm-strip` name-section removal were investigated but found already-applied by PackageToJS, so neither was added as a required step. The audit doc (`docs/perf/2026-05-26-wasm-bundle-audit.md`) records the baseline, top-30 function attribution, and the conclusion that the dominant cost is the Apple-pre-compiled stdlib + Foundation. Phase 14b Track 1 (Service Worker Cache) complete — first visit at ~18 MB gzipped; repeat visits hit local cache. `swiflow build` now emits `swiflow-manifest.json` at the project root with SHA256s of each artifact; the SW splits cache namespaces between WASM and JS runtime so a Swift-source edit doesn't invalidate the JS runtime cache and vice versa. Phase 14a (Bundle Size CI) — `scripts/measure-bundle.sh` + `bundle-size` CI job now enforce a 5%-growth budget on every PR. Phase 13e (Confidence Fixes) complete — 11 audit gaps closed across public API hygiene (`Patch`/`PatchPayload`/`PatchSerializer`/`HandleAllocator`/`MountNode` demoted to `package`; `TestNode.properties` no longer leaks `PropertyValue`), `@Environment` correctness (`EnvironmentValues: Equatable`; postfix `.environment()` modifier; VNode diff now detects env changes), CLI distribution readiness (`--swiflow-version` flag + `SwiflowDep` enum), and Router test coverage (`@Environment(\.router)` propagation across `embed {}` verified; Playwright URL/history test added). Also fixed a Phase 13d WASM cross-compile regression — `@Component` classes now require an explicit `@MainActor` because Swift 6 won't propagate isolation through a macro-emitted extension.
Phase 13d (Macro Diagnostics & @Component) introduced the macro and `@ChildrenBuilder` builder-block diagnostics guiding scalar types to `text(…)`. Phase 13c (Multi-Root & Unmount) added multiple independent component trees at different DOM selectors with clean resource release via `Swiflow.unmount(into: selector)`. Phase 13b (Browser Debugging) shipped DWARF symbols, full-viewport error overlays, and Chrome DevTools debugging guide. Phase 13a (SwiflowTesting) added the headless test harness (`render()`, `click()`, `input()`, `findAll()`). Earlier: Phase 12b (Form Validation),
Phase 11 (Router), Phase 8 (HMR — state-preserving WASM hot swap), Phase 7
(Bindings, Refs & Form Foundations).

## Quick start

```bash
# 1. Build the CLI.
swift build -c release --product swiflow

# 2. Scaffold a project. The generated Package.swift pins to the matching
#    Swiflow release (same version as this CLI binary) — no extra flags
#    needed once 0.1.3+ is published.
./.build/release/swiflow init my-app
cd my-app

# 3. Run the dev server — builds the WASM, serves on :3000, full-reload on save.
../.build/release/swiflow dev
# Open http://localhost:3000
```

**Hacking on Swiflow itself?** Pass `--swiflow-source $(pwd)` to `init`
so the generated project depends on your local clone instead of the
published release:

```bash
./.build/release/swiflow init my-app --swiflow-source $(pwd)
```

See [docs/guides/debugging.md](docs/guides/debugging.md) for Chrome DevTools setup and Swift source breakpoints.

For one-shot production builds, `swiflow build` wraps `swift package js` with
the right WASM SDK and toolchain auto-detection.

## Prerequisites

- **Swift 6.3** — `swift --version` should report 6.3.x. CI pins 6.3.0 because
  the WASM SDK's stdlib must match the host compiler exactly.
- **macOS 14+** (host requirement for the dev server, which uses Hummingbird 2.x).
  Linux works without a version pin.
- **WebAssembly Swift SDK 6.3** — install once via:
  ```bash
  swift sdk install \
    https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz \
    --checksum 9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9
  ```

Run `swiflow doctor` after building the CLI to verify your toolchain is complete:
```bash
./.build/release/swiflow doctor
```

## What's in the box

- **`Swiflow`** — pure-Swift VDOM core: tagged-enum `VNode`, 19-opcode `Patch`,
  hybrid keyed (LIS-based) + indexed children diff, `@resultBuilder` DSL.
- **`Component` + `@State`** — reactive class-bound components. `@State` is an
  attached Swift macro that emits an accessor `didSet` calling into the
  per-frame `RAFScheduler` on mutation, plus a `$`-prefixed `Binding<T>`
  projection. Lifecycle hooks (`onAppear`, `onChange`, `onDisappear`) fire on
  every component in the mount tree — children-first on mount, parent-first
  on unmount.
- **Security** — `URLSanitizer` scrubs `javascript:` / `vbscript:` / `data:` /
  `blob:` from `href`, `src`, `action`, `formaction` at the DSL fold step.
  `VNode.rawHTML(_:)` is the named-loud escape hatch.
- **Debug diagnostics** — `swiflowDiagnostic` (`#if DEBUG`, compiled to nothing in
  release) catches three programmer-error footguns: duplicate keys among
  siblings, mixed keyed/unkeyed siblings, component-body anchor cycles
  (depth ≥ 32).
- **`SwiflowWeb`** — WASM-only renderer + JavaScriptKit bridge.
- **`swiflow` CLI** — `init` scaffolds, `build` wraps `swift package js`, `dev`
  starts a Hummingbird HTTP + WebSocket server with file-watch full-reload.
- **JS driver** — vanilla JS, ~200 lines, embedded into the CLI binary as
  generated Swift code (single source of truth: `js-driver/swiflow-driver.js`).

## Architecture

See [docs/superpowers/specs/](docs/superpowers/specs/) for per-phase design
specs and [docs/superpowers/plans/](docs/superpowers/plans/) for the executable
implementation plans. [docs/brainstorm/](docs/brainstorm/) holds the original
design exploration.

## Testing

```bash
# Swift core: 548 tests across 108 suites.
# WASM-SDK-gated E2E tests skip cleanly when no SDK is installed.
swift test

# JS driver: 32 jsdom-based unit tests covering driver opcodes, dev reload, and service worker.
(cd js-driver && npm test)
```

Playwright e2e (Counter, Router, Progress, SW-cache) lives in
`Tests/playwright/` and is opt-in. Four per-suite npm scripts target
just one server each for fast local iteration:

```bash
cd Tests/playwright
npm run test:counter   # @State + Counter, dev server on :3000   (~1 min)
npm run test:router    # SwiflowRouter + Link + Back, on :3001   (~1 min)
npm run test:sw        # service-worker cache + progress UI      (~5 min, release build)
npm test               # all of the above + cross-server scenarios (~20 min)
```

See [`Tests/playwright/README.md`](Tests/playwright/README.md) for the
full breakdown of what each spec covers and the rationale for the
per-suite splits.

## License

Apache 2.0. See [LICENSE](LICENSE).
