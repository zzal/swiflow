# Changelog

All notable user-facing changes to Swiflow.

Swiflow is pre-1.0; APIs can change in any minor phase. Each phase below
carries a **Stability** note that indicates whether its surface is intended
for current use or is forward-looking infrastructure:

- **Stable for pre-1.0 usage** — intended for current use; breaking changes
  are flagged explicitly in later phases.
- **Experimental — interface may change** — intentionally subject to redesign.
- **Forward-looking infrastructure — not yet live** — in tree but not yet
  functional end-to-end.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com).

---

## [Phase 14b — Track 3] — 2026-05-26

**Stability:** Driver-side enhancement. No Swift API moves, no new
prereqs, no breaking change.

### Added
- `fetchWithProgress` helper in `swiflow-driver.js`: streams the WASM
  fetch via `getReader()` and writes the percent to
  `document.documentElement.dataset.swiflowProgress`. Cancels the
  reader on mid-stream errors so connections release immediately.
- Default `[data-swiflow-progress]` CSS rule in `swiflow init`
  scaffold so new projects show a "Loading N%" overlay out of the
  box. Users style or remove freely.
- Playwright `progress.spec.ts` covering the attribute path against
  the SW config's release static server.

### Changed
- Driver boot pre-fetches `App.wasm` and hands the `Response` promise
  to PackageToJS `init({ module })` instead of letting PackageToJS
  run its own fetch. On cache hits (Track 1 service worker) the
  stream completes within a tick and the attribute jumps straight
  to "100" with no flash.

### Constraints
- When `Content-Length` is absent (some CDN configurations) the
  driver does not write intermediate percents — only the final
  `"100"`. The CSS rule
  `html[data-swiflow-progress]:not([data-swiflow-progress="100"])`
  stays dormant in that case rather than showing a misleading "0%"
  indefinitely.
- Synchronous failure of the progress fetch falls back to PackageToJS's
  default internal fetch. Asynchronous rejection surfaces as a
  "WASM init failed" console warning — intentional, so users see
  hard fetch errors instead of silent failure.

---

## [Phase 14b — Track 2] — 2026-05-26

**Stability:** Measurement and modest trim. No functional behaviour
change. No Swift API moves.

### Added
- `swiflow doctor` subcommand — standalone toolchain audit. Checks
  swift + the WASM SDK and prints install hints when anything is
  missing.
- `docs/perf/2026-05-26-wasm-bundle-audit.md` — baseline audit of
  the HelloWorld WASM with section sizes, top-30 functions, attribution
  buckets, and the reflection-disabled lower-bound measurement.

### Changed
- Release builds now compile with `-Osize -gnone` instead of `-O`,
  shaving ~37 KB (0.21%) off the gzipped bundle.
- `docs/perf/bundle-baseline.json` refreshed to the actual measured
  baseline (18.2 MB gzipped); the previous figure (20.6 MB) predated
  the current PackageToJS pipeline.

### Investigated and dropped
- `wasm-opt -Oz` post-processing — pre-flight measurement showed
  0.06% gzipped savings because PackageToJS already runs `wasm-opt -O`
  internally. Adding a required Binaryen dependency for marginal
  reduction was the wrong trade.
- `wasm-strip` name-section drop — PackageToJS already omits the
  name section from the shipped artifact.

### Audit conclusions
- The dominant cost is the Apple-pre-compiled Swift stdlib + Foundation,
  not user-code optimisation flags. Top-30 function attribution is
  in the audit doc.
- The next meaningful trim lever is removing the `Mirror` dependency
  in `@State`, which would unlock `-disable-reflection-metadata`.
  That's a post-1.0 API redesign, not a Track 2 follow-up.

---

## [Phase 14b — Track 1] — 2026-05-26
**Stability:** Stable for pre-1.0 usage. Auto-registered in release builds, skipped in `swiflow dev`.

### Added
- Service worker (`swiflow-sw.js`) that pre-caches the WASM and the JS runtime keyed by content hash. Repeat visits transfer ~0 bytes for unchanged artifacts. Two independent caches (`swiflow-wasm-v<sha8>`, `swiflow-runtime-v<sha8>`) so a Swift-source edit doesn't invalidate the JS runtime cache and vice versa.
- `swiflow build` emits `swiflow-manifest.json` at the project root (next to `swiflow-sw.js`) listing SHA256 of every shipped artifact. The SW reads it on install to know what to cache.
- Driver auto-registers the service worker on release builds; in dev, it auto-unregisters any `swiflow-sw.js`-scoped SW so HMR doesn't fight a stale cache.
- Driver now owns the dynamic `import()` of the PackageToJS entry — user `index.html` is one `<script>` tag lighter; the init template ships only `<script src="swiflow-driver.js"></script>`.
- `npm run test:sw` (in `Tests/playwright/`) — fast local SW e2e via a split config that skips the dev and router-demo servers.

### Changed
- `swiflow init` scaffolds `swiflow-sw.js` alongside `swiflow-driver.js`.
- `examples/HelloWorld/index.html` drops the `<script type="module">import { init }</script>` block. Existing user projects should do the same — or leave the block in place, where it becomes redundant (the driver's idempotency guard prevents double-init).
- `Templates`-vs-`examples/HelloWorld` sync is now enforced for the JS files too: `TemplatesTests` asserts byte-equality of `swiflow-driver.js` and `swiflow-sw.js` against the canonical `js-driver/` sources.

### Fixed
- WASM init failure now surfaces a `console.warn` instead of being silently swallowed. A 404 on the PackageToJS entry or an exception inside `init()` no longer leaves the page silently dead.

---

## [Phase 14a] — 2026-05-25
**Stability:** CI infrastructure — no source-level API changes.

### Added
- Bundle size CI gate. `scripts/measure-bundle.sh` builds the Counter example in release, sums `App.wasm` + all PackageToJS `.js` outputs (raw + gzipped), and writes `current-bundle.json`. `scripts/compare-bundle.sh` diffs against the committed `docs/perf/bundle-baseline.json`.
- New `bundle-size` PR-only job in `.github/workflows/ci.yml` runs both scripts and posts a sticky comment with the diff table.
- Gate: PR fails if total gzipped bundle grows >5% (overridable with the `bundle-size-skip` label) or unconditionally fails at >20%.
- Initial baseline: 59 MB raw / 20 MB gzipped WASM, 55 KB / 12 KB gzipped JS runtime — total **20.6 MB gzipped on the wire** for the Counter example.

### Changed
- `README.md` "Costs" section now points at `docs/perf/bundle-baseline.json` as the source of truth instead of inlining a hand-written byte count that would drift.

---

## [Phase 13f] — 2026-05-25
**Stability:** Polish only — no API surface changes; closes 3 audit minor items.

### Added
- `TestHarness.change(_:at:value:)` for testing `<select>` and `<textarea>` `onChange` handlers (closes A5).
- `CHANGELOG.md` with retroactive entries from Phase 7 (closes A6).

### Fixed
- `swiflow init` cleans up the target directory when a file write fails partway through (closes C4).

---

## [Phase 13e] — 2026-05-25
**Stability:** Stable for pre-1.0 usage. `--swiflow-version` is forward-looking — its placeholder URL has no live release yet.

### Added
- `.environment(_:_:)` postfix VNode modifier (alongside existing `withEnvironment`).
- `--swiflow-version <version>` flag and `SwiflowDep` enum for URL-based generated `Package.swift`.
- `examples/RouterDemo` + `Tests/playwright/router.spec.ts` hash-mode router end-to-end test.
- `docs/guides/testing.md` user guide for `SwiflowTesting`.
- Verified `@Environment(\.router)` propagation across `embed {}` boundaries.

### Changed
- `TestNode.properties` now returns `[String: String]` (was `[String: PropertyValue]`).
- `EnvironmentValues` conforms to `Equatable` via type-erased equality; `VNode` diff now detects environment changes correctly (was silently skipping subtrees on env-only differences).

### Fixed
- WASM cross-compile regression from Phase 13d: `@Component` classes now require explicit `@MainActor` (canonical pattern: `@MainActor @Component final class Foo`). Swift 6 doesn't propagate isolation retroactively through macro-emitted conformance extensions.
- Dev driver RAF shim guarded for environments without `requestAnimationFrame` (fixed JS driver tests under jsdom).

### Breaking
- `Patch`, `PatchPayload`, `PatchSerializer`, `HandleAllocator`, `MountNode` demoted from `public` to `package` access. No external code should have been using these.
- `Templates.packageSwift` and `ProjectWriter.writeProject` signatures: `swiflowSource: String` → `swiflowDep: SwiflowDep`.

---

## [Phase 13d] — 2026-05-25
**Stability:** Stable for pre-1.0 usage. The `@Component` macro requires explicit `@MainActor` — see Phase 13e for the correction that landed shortly after.

### Added
- `@Component` macro (`MemberAttributeMacro` + `ExtensionMacro`) — classes annotated with `@MainActor @Component final class Foo` automatically receive the `Component` protocol conformance without writing `: Component` by hand.
- `SwiflowMacrosPlugin` macro target and `SwiflowMacrosTests`.
- `text(_:)` free functions for `String`, `Int`, `Double`, and `Bool` scalars — the canonical way to produce a text VNode when the result builder's type inference can't help.
- `@ChildrenBuilder` `unavailable` overloads for scalar types that emit actionable `Use text(…)` diagnostics at the call site.

### Changed
- The `init` project template and `examples/HelloWorld` updated to the `@MainActor @Component` declaration form.

---

## [Phase 13c] — 2026-05-24
**Stability:** Stable for pre-1.0 usage.

### Added
- Multi-root mount: `Swiflow.render(into: selector) { ... }` can now be called for multiple independent DOM selectors in the same page.
- `Swiflow.unmount(into: selector)` for clean teardown — releases the renderer, closes all handler scopes, and removes DOM children.
- `DevAPI.installAll()` reports all mounted roots keyed by selector when called from the browser console.

### Changed
- Internal `HandlerRegistry` gained a global handler-ID counter and dispatch table so events from multiple component trees route correctly. This is an internal refactor with no public API changes.

---

## [Phase 13b] — 2026-05-23
**Stability:** Stable for pre-1.0 usage.

### Added
- DWARF debugging symbols emitted in dev builds — Swift source-level breakpoints and stack traces now work in Chrome DevTools via the C/C++ DevTools Extension.
- Full-viewport dev-mode error overlay: unhandled Swift panics / JS errors are surfaced as a red overlay with the stack trace, rather than silently failing.
- `docs/guides/debugging.md` — Chrome DevTools setup guide covering DWARF symbols, the C/C++ DevTools Extension, Memory Inspector usage, and `window.__swiflow` console access.

---

## [Phase 13a] — 2026-05-22
**Stability:** Stable for pre-1.0 usage. `AsyncTestRenderer` (for `task {}` lifecycle hooks) is forward-looking infrastructure — not yet live.

### Added
- `SwiflowTesting` module — headless test harness that runs the Swiflow VDOM engine without a real DOM.
- `render(_:)` entry point returns a `TestHarness` bound to the rendered tree.
- `TestHarness` query API: `find(tag:)`, `findAll(tag:)`, `exists(tag:)`, `findComponentNode(_:)`.
- Interaction helpers: `click(on:)`, `input(on:value:)`, `blur(on:)`.
- `TestNode` — lightweight view of a mount-tree node exposing tag, text content, and `properties: [String: String]`.
- Full `Counter` and `SignIn` spec suites in `Tests/SwiflowTests/`.

---

## [Phase 12b] — 2026-05-22
**Stability:** Stable for pre-1.0 usage.

### Added
- `FormController<Fields>` — reactive coordinator that owns field values, validation state, and submission lifecycle.
- `Field<Value>` — typed field descriptor carrying initial value, validators, and blur-triggered error display.
- `@FieldBuilder` result builder for composing field sets.
- `Form` helper that binds a `FormController` to a VNode subtree.
- Built-in validators: `.required()`, `.email`, `.minLength(_:)`, `.custom(_:message:)`.
- `touchAll()` forces all fields to validate at once (e.g., on submit). `reset()` clears all field state. `isValid` computed property gates submission.
- `SignIn` demo in `examples/HelloWorld` exercising the full form flow.

---

## [Phase 12a] — 2026-05-21
**Stability:** Stable for pre-1.0 usage.

### Added
- `css { }` result builder for constructing `CSSSheet` values inline.
- `rule(_:) { }` block for targeting a CSS selector, `keyframes(_:) { }` for animation definitions. `from { }`, `to { }`, `at(_ percent:) { }` keyframe stop blocks.
- ~50 CSS property builder functions (`color`, `backgroundColor`, `fontSize`, `display`, `flexDirection`, `opacity`, `transform`, etc.).
- `static var scopedStyles: CSSSheet?` hook on `Component` — the sheet is injected as a `<style>` tag and class-scoped automatically at mount so styles don't leak across components.
- `static var exitAnimation: String?` + `exitDuration` — the JS driver plays the named keyframe animation before removing a node from the DOM.
- `.transition(_:)`, `.animation(_:)`, `.cssVar(_:_:)` postfix VNode modifiers.
- `Counter + Toast` demo in `examples/HelloWorld` showing scoped styles and exit animations.

---

## [Phase 11] — 2026-05-21
**Stability:** Stable for pre-1.0 usage.

### Added
- `SwiflowRouter` module — hash-mode and history-mode client-side routing.
- `RouterRoot { }` DSL component — declares the route tree and owns current-path `@State`.
- `Route(_:) { }` and `Route(_:) { ctx in }` — flat and parameterised route definitions, composable via `@RouteBuilder`.
- `Link` component — `label:` and `children:` variants; intercepts clicks and calls `router.navigate`.
- `Router` value exposed via `@Environment(\.router)` — provides `path`, `params`, `query`, `navigate(_:)`, `replace(_:)`, `back()`.
- `examples/MiniRouter` — 3-page demo with programmatic navigation.
- `docs/guides/router.md` — user guide covering hash mode, history mode, nested routes, and `@Environment(\.router)` access.

---

## [Phase 10] — 2026-05-21
**Stability:** Stable for pre-1.0 usage.

### Added
- `EnvironmentKey` protocol + `EnvironmentValues` struct — extensible typed key-value store threaded through the VNode diff.
- `@Environment(\.keyPath)` property wrapper — reads the in-tree environment during `body` evaluation.
- `withEnvironment(\.key, value) { child }` DSL function — overrides environment values for a VNode subtree without introducing a new component class.
- Built-in environment keys: `locale: String`, `colorScheme: ColorScheme`.
- `Component.onChange(of:key:perform:)` — fires the callback only when the observed value changes between renders; uses a side table keyed by instance identity so it requires no protocol change.
- `docs/guides/environment.md` — covers `@Environment`, `withEnvironment`, and `onChange(of:)`.

---

## [Phase 9] — 2026-05-20
**Stability:** Stable for pre-1.0 usage. The DOM-overlay component inspector remains forward-looking infrastructure — not yet live.

### Added
- `window.__swiflow` browser console API (dev mode only):
  - `.tree()` — indented string of the live mount tree.
  - `.state(path)` — `@State` values for the component at a given path.
  - `.handlers()` — handler counts per scope from `HandlerRegistry`.
  - `.perf()` — render count, last patch count, last render time in ms.
- `Renderer` perf counters (`renderCount`, `lastPatchCount`, `lastRenderMs`).
- `docs/guides/devtools.md` — browser console guide.

---

## [Phase 8] — 2026-05-20
**Stability:** Stable for pre-1.0 usage.

### Added
- State-preserving WASM hot swap on every save (`swiflow dev`). The browser fetches the new WASM module, the runtime snapshots `@State` from the old module, the new module rebuilds the tree seeded with that state, and the DOM is patched — no full page reload.
- JS driver logs `[swiflow] hmr-swap took Xms` per swap.
- `@State` cells of `String`, `Int`, `Double`, and `Bool` survive across saves. Shape changes (renamed or reordered fields) fall back to a full page reload.
- `window.SWIFLOW_HMR` flag injected by the dev server activates the HMR branch; production builds are unaffected.
- `docs/perf/2026-05-20-hmr-baseline.md` — measured save→pixels baseline on M1 Max with Swift 6.3 / WASM SDK 6.3.

---

## [Phase 7] — 2026-05-20
**Stability:** Stable for pre-1.0 usage. This is when the public component API crystallized.

### Added
- `@State` property wrapper with Mirror-based wiring to `RAFScheduler` — mutations trigger a batched re-render on the next animation frame.
- Two-way bindings: `.value($text)` for `String`, `Int`, `Double`; `.checked($flag)` for `Bool`; `.selection($choice)` for `String` selects.
- `Ref<Element>` — first-party DOM access for focus, scroll, and arbitrary method calls without dropping to JavaScriptKit directly. Attached via `.ref($myRef)`.
- `textarea`, `select`, `option` element factories (completing the form-input DSL alongside the existing `input`).
- Typed `EventInfo` accessors: `targetChecked: Bool?`, `targetValueInt: Int?`, `targetValueDouble: Double?`.
- `onAppear`, `onChange`, `onDisappear` lifecycle hooks on `Component`.
- `docs/guides/forms.md` — form-input guide covering bindings, refs, and the text-input demo.
