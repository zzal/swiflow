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

**Status:** Phase 12a (Styling & Animation) — CSS-in-Swift scoped styles, keyframe animations, enter/exit transitions, CSS variables bridge.

**What works today (Phase 12a):**
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
- 436+ tests, Playwright e2e, DWARF debugging guide, `docs/guides/forms.md`.

**What's not in the box yet:**
- **Component inspector / devtools** — Phase 9.
- **`@Environment` / context DI** — Phase 10.
- **Router** (`SwiflowRouter`) — Phase 11.
- **Form validation framework** — Phase 12b+.
- **Multi-root rendering, lazy components, component testing harness,
  macro diagnostics** — Phase 13.

**Costs you should know:**
- **WASM bundle (Counter example, release):** ~59 MB (`.wasm` only);
  ~59 MB total payload with the JS runtime. Order-of-magnitude
  larger than a Vite-built JS app — that's the Swift-on-WASM tax.
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

**Status:** Phase 11 (Router) complete. `SwiflowRouter` ships with hash
and history modes, param binding, nested routes, programmatic navigation,
and 422 passing tests. See `docs/guides/router.md` for the user guide.
Phase 8 (HMR & The Instant Dev Loop) delivered hot module swap on every
save: the browser fetches the new WASM, the runtime captures the live
`@State` snapshot from the running module, restores it into a fresh tree,
and repaints — all without a full page reload. `@State` survives across
saves. The Counter template's `count` stays at whatever you clicked it
to; the greeting input keeps whatever you typed. Phase 7 (Bindings, Refs
& Form Foundations) is the layer this builds on.

## Quick start

```bash
# 1. Build the CLI.
swift build -c release --product swiflow

# 2. Scaffold a project.
./.build/release/swiflow init my-app --swiflow-source $(pwd)
cd my-app

# 3. Run the dev server — builds the WASM, serves on :3000, full-reload on save.
../.build/release/swiflow dev
# Open http://localhost:3000
```

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

## What's in the box

- **`Swiflow`** — pure-Swift VDOM core: tagged-enum `VNode`, 16-opcode `Patch`,
  hybrid keyed (LIS-based) + indexed children diff, `@resultBuilder` DSL.
- **`Component` + `@State`** — reactive class-bound components with a Mirror-wired
  `@State` property wrapper that calls into the per-frame `RAFScheduler` on
  mutation. Lifecycle hooks: `onAppear`, `onChange()`, `onDisappear`.
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
swift test
```

281 tests across 59 suites. Tests that require the WASM SDK end-to-end are
gated and skip cleanly when it's absent.

## License

Apache 2.0. See [LICENSE](LICENSE).
