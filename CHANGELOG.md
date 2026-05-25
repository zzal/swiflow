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
