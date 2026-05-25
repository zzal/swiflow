# Swiflow DX Uplift — Master Plan (Phases 6 → 13)

> **Motto:** "The single most important thing Swiflow can do between now and 1.0 is to make `save → pixels` feel instant. Everything else is downstream of that."

---

## Context

Swiflow just shipped **Phase 5 (API Polish)**. The post-Phase-5 surface was then evaluated by the `swift-innovator-expert` agent through the eyes of a frontend engineer who has never written Swift (`docs/reviews/swift-innovator-expert/2026-05-19-swiflow-dx-for-frontend-engineers.md`).

The verdict: the *core API is the best frontend-shaped Swift web DSL in existence*, but **Swiflow is not yet pitchable to a frontend engineer for a side project** because of:

1. A full-reload dev loop that drops state on every save.
2. Two pre-1.0 bugs that erode trust on first read (`.attr(_:_:Bool)` is a no-op; `Binding<Value>` ships without a consumer).
3. Missing ecosystem capabilities a React/Vue/Svelte engineer expects on day one: HMR, devtools, router, refs, @Environment, scoped CSS, animation, forms, multi-root rendering, component-level testing.

The `executing-plans` and `subagent-driven-development` flow that landed Phase 5 will be reused. Each phase below is sized comparably to Phase 5 (≤10 tasks) so it ships in one focused session.

This plan **supersedes** the older drafts in `docs/superpowers/plans/`:
- `2026-05-17-swiflow-phase2b-cli.md` — already shipped (kept for archaeology).
- `2026-05-18-swiflow-phase2b3-cosmetics-cleanup.md` — folded into Phase 6.
- `2026-05-18-swiflow-phase2c-dev-server.md` — already shipped; the HMR work in Phase 8 builds on top of it.
- `2026-05-18-swiflow-phase3-reactivity.md` — already shipped.

---

## Phase 6 — Trust & Polish

**Goal:** Eliminate every credibility-erosion item before HMR lands so the post-HMR "wow" isn't immediately followed by a "wait, this is broken."

**Findings addressed:** (from §4 of the assessment) #8 (Binding ship-or-hide decision), #9 (attr Bool no-op), the `final class` template footgun, README honesty re: bundle size and cold-build time, the `embed { }` factory contract being too quiet.

**Scope:**
- Fix `.attr(_:_:Bool)` overload in both `Sources/Swiflow/DSL/Modifiers.swift:41-43` and `Sources/Swiflow/DSL/VNodeModifiers.swift:42-44`: omit the attribute entirely when `value == false` (matches HTML semantics; aligns with `disabled`, `checked`, `readonly` behavior).
- Add `final class Counter` explainer comment to `Sources/SwiflowCLI/Templates/Templates.swift` and `examples/HelloWorld/Sources/App/App.swift` — one line pointing at `Component.swift` for the why.
- Loudify the `embed { }` factory contract: doc-comment in `Sources/Swiflow/DSL/ComponentDSL.swift` becomes a warning header; add a DEBUG-only `swiflowDiagnostic` if the same instance is returned twice.
- README rewrite: add an honest "what to expect today" section covering WASM bundle size (measured), cold-build time, hot-build time, what works, what doesn't yet.
- Decision committed: **Binding<Value> ships in Phase 7**. The `@_documentation(visibility: internal)` annotation on Binding stays until then — frontend devs no longer trip on it via autocomplete in Phase 6.
- Fold in Phase 2b.3 cosmetics: template path comment, `DriverEmbedder` access-level tightening, `WasmSDKProbe` stderr surfacing.
- Status line in README → "Phase 6 (Trust & Polish)".

**Why this phase first:** every other phase loses 30% of its impact if a new user lands on a typo'd README, a broken `.attr`, or a stubbed Binding. Cheap to ship, biggest perception multiplier.

---

## Phase 7 — Bindings, Refs & Form Foundations

**Goal:** Finish what Phase 3 declared. Make forms possible without dropping to JavaScriptKit.

**Findings addressed:** Translation-cost-table rows for **Two-way binding** (High), **Refs** (High), **Forms** (High); §4 #8 (Binding consumer); §5 row "Two-way input binding" (High); §5 row "Refs / direct DOM access" (Medium).

**Scope:**
- DSL consumer for `Binding<Value>` (`Sources/Swiflow/Reactivity/State.swift:108-116`):
  - `.value(_:Binding<String>)` on `input`, `textarea`
  - `.value(_:Binding<Int>)`, `.value(_:Binding<Double>)` with parsing fallback
  - `.checked(_:Binding<Bool>)` on `input[type=checkbox]`
  - `.selection(_:Binding<String>)` on `select`
- Internally: each binding modifier registers an `.input` (or `.change`) handler against the active component's HandlerRegistry scope. Round-trip verified via integration test.
- `Ref<Element>` first-party type in `Sources/Swiflow/Reactivity/Ref.swift` + `.ref($fieldRef)` modifier. Populated post-mount via a new Diff hook; cleared on unmount via existing scope close.
- `EventInfo.targetValue` polish: typed accessors (`targetIntValue`, `targetBoolValue`, `selectedOptions`).
- A documented form-handling recipe in `docs/guides/forms.md` showing controlled-input + validation pattern (validation itself ships fully in Phase 12).
- Counter template additions: a small text-input demo in `examples/HelloWorld` exercising `.value($text)` and `.ref($inputRef)`.

**Why second:** Phase 8 HMR is the centerpiece, but HMR shipped on top of an unfinished Binding loses its biggest demo (state-preserving input typing). Bindings + Refs make the HMR "wow" land properly.

---

## Phase 8 — HMR & The Instant Dev Loop ⭐ (motto centerpiece)

**Goal:** Replace `location.reload()` with a true module hot-swap that preserves `@State` across saves.

**Findings addressed:** §4 #1 (full-reload dev loop — the #1 blocker), §4 #2 (WASM build time perception), §4 #10 (single-root assumption — relaxed in dev mode here, fully removed in Phase 13), §5 row "HMR preserving component state" (Critical), the motto.

**Scope:**
- New module hot-swap pipeline in `Sources/SwiflowCLI/DevServer/` and `js-driver/swiflow-driver.js`:
  - On rebuild success, broadcast `{"type":"hmr-swap","url":"/dist/app.wasm?h=..."}` instead of `{"type":"reload"}`.
  - JS driver fetches the new WASM, instantiates a second module, hands the new root factory to a new entry point.
- New public API in `Sources/SwiflowWeb/SwiflowWeb.swift`: `Swiflow.hmrSwap(into: selector, _ factory: () -> Component)`:
  - Locates the existing `ambientRenderer` for `selector`.
  - Walks the existing mount tree; for each Component, looks up matching `(typeID, key)` in the new tree.
  - **Migrates `@State` boxes** from old → new Component instance via the existing Mirror-wiring path (`wireState(on:scheduler:)`).
  - Diffs and applies — DOM nodes survive; handlers re-register against the existing HandlerRegistry scope.
- Single-root `precondition` (`Sources/SwiflowWeb/SwiflowWeb.swift:43-48`) **relaxed in dev mode** (gated on `window.SWIFLOW_DEV`); full lift comes in Phase 13.
- DWARF / source-map UX pass: ensure browser stack traces point at the `.swift` file. Document the debugger story.
- Build-cache hygiene: skip linker steps when only Swift sources changed; aim for sub-3-second incremental rebuild on the Counter template.
- Failure mode handling: if the hot-swap fails (e.g., a typeID changed because the user renamed a Component), fall back to full reload with a console warning explaining what happened.
- Status line: "Phase 8 (HMR & The Instant Dev Loop)".

**Verification:** save → pixels measurement on the Counter template, before vs. after. Target: <1 second from save to repainted DOM, with `count` preserved.

**Why third:** the motto. Every downstream phase ships faster once this works.

---

## Phase 9 — Devtools: Component Inspector

**Goal:** Give a frontend engineer the React-DevTools-shaped affordance they expect.

**Findings addressed:** §4 #5 (no devtools), §5 row "Component inspector / state inspector" (High), §3 win #6 (HandlerRegistry scoping — now visible).

**Scope:**
- `window.__swiflow__` API installed when `SWIFLOW_DEV === true`. Lives in a new `Sources/SwiflowWeb/DevAPI.swift` (gated by `#if DEBUG` or the WASM-side equivalent).
- `__swiflow__.tree()` — pretty-prints the live mount tree (component name, typeID, key, child count).
- `__swiflow__.state(componentPath)` — dumps `@State` values for the component at a given mount-tree path.
- `__swiflow__.handlers()` — reports HandlerRegistry sizes per scope; useful for spotting leaks.
- `__swiflow__.perf()` — render counts, last-diff size, frame budget consumed.
- Optional in-page DOM overlay (toggle via `__swiflow__.overlay()`) outlining each Component's root element with its name.
- Tutorial doc in `docs/guides/devtools.md`.
- Status line: "Phase 9 (Devtools)".

**Verification:** open Counter in browser, run `__swiflow__.tree()` and `__swiflow__.state('Counter')`, confirm output matches the source.

---

## Phase 10 — Effects, Context & @Environment

**Goal:** Stop forcing global singletons or constructor-prop-drilling for cross-tree concerns. Give `onChange` a deps-aware shape.

**Findings addressed:** Translation table rows **Hooks / Effects** (Medium-high) and **Context / DI** (High); §5 rows "useEffect-style deps array" (Medium) and "Context / EnvironmentObject" (Medium); §4 (no row, but implied in the `onChange` discussion).

**Scope:**
- `onChange(of: value)` lifecycle hook variant on `Component` that fires only when `value` changes between renders (compared via `Equatable`).
- Async-friendly Task-aware lifecycle: `task { }` block that's cancelled on unmount, following SwiftUI's `.task` precedent.
- `@Environment(\.keyPath)` property wrapper + `EnvironmentValues` extension point. Type-keyed DI down the component tree.
- Built-in environment keys: `locale`, `colorScheme`, `theme`. Router environment (\.route, \.navigate) defined here but used in Phase 11.
- `withEnvironment(\.key, value) { … }` builder block for in-tree overrides.
- Component-level dependency injection example in `docs/guides/environment.md`.
- Status line: "Phase 10 (Effects & Environment)".

**Why before Router:** SwiflowRouter (Phase 11) exposes `@Router` and route params via `@Environment`. Building Environment first means Router gets the same DI mechanism every app will use.

---

## Phase 11 — SwiflowRouter

**Goal:** Ship a first-party router so multi-page side projects become buildable.

**Findings addressed:** Translation table row **Router** (High); §5 row "Router" (High); §6 readiness item #3.

**Scope:**
- New product target `SwiflowRouter` in `Package.swift`. Depends on `Swiflow`; not on `SwiflowWeb` directly (router is platform-agnostic, web bridge ships in same module).
- Declarative routes:
  - `Route("/path") { HomePage() }`
  - `Route("/users/:id") { ctx in UserPage(id: ctx.params["id"]!) }`
  - `Routes { ... }` container that selects based on current path.
- `Link("/path", "Label")` and `Link("/path") { children }` — in-app navigation that uses `history.pushState` (history mode) or `location.hash` (hash mode), no full reload.
- `@Environment(\.router)` access for programmatic navigation: `router.navigate("/dashboard")`.
- Hash-mode router for static hosts; history-mode for SSR-friendly hosts. Configurable at `RouterRoot(.history) { … }`.
- Nested routes with relative path resolution.
- Lazy route loading hook — `LazyRoute("/heavy") { import("./HeavyPage") }` — even if the WASM doesn't truly split in Phase 11; deferred-init is enough for now. Full code-splitting in Phase 13.
- Example app: `examples/MiniRouter/` — a 3-page app with nav.
- Status line: "Phase 11 (Router)".

---

## Phase 12 — Styling, Animation & CSS Scoping

**Goal:** Close the styling, animation, and form-validation gaps in one ecosystem-shaped phase.

**Findings addressed:** Translation table rows **CSS** (Medium), **Animation** (High for marketing pages); §5 rows "Scoped CSS" (Medium), "Animation primitives" (Low-medium), "Form helpers / validation" (Medium-high — folded in here because validation is mostly styling-and-feedback work).

**Scope:**
- Scoped CSS story (pick one — `brainstorming` skill recommended at phase kickoff):
  - **Option A**: compile-time per-component class-name mangling (`.swiflow-Counter-container`).
  - **Option B**: CSS Modules-like `@CSS` macro reading a `.css` sibling.
  - **Option C**: CSS-in-Swift `style { … }` builder.
- Animation primitives:
  - `.transition(_:on:)` modifier on VNode (declarative; uses CSS `transition` under the hood).
  - `.animation(_:value:)` SwiftUI-shaped helper.
  - Enter/exit transitions for components added/removed from `@ChildrenBuilder`.
- CSS variables bridge: write `@State` → CSS custom property, read CSS variable → `@State`. Useful for theme switching.
- Form validation primitives:
  - `Field<Value>` wrapper with `.error`, `.touched`, `.dirty`.
  - `Form { … }` builder coordinating multiple fields.
  - Built-in validators (`.required`, `.minLength`, `.regex`).
  - Async validator support (uses Phase 10's `task { }`).
- Status line: "Phase 12 (Styling, Animation & Forms)".

---

## Phase 13 — Maturity & 1.0 Readiness

**Goal:** Close out everything else and freeze the 1.0 surface.

**Findings addressed:** §4 #10 (single-root removal — full lift here), §4 #6 (builder error messages — macro diagnostics), §5 rows "Bundle splitting / lazy components" (Medium), "Testing story for components" (Medium), "TypeScript-grade error messages" (Medium); §6 readiness item #7 (bundle / cold-build documentation in CI).

**Scope:**
- Lift the single-root `precondition` entirely in `Sources/SwiflowWeb/SwiflowWeb.swift:43-48`. Multiple `Swiflow.render(into:)` calls supported with separate `ambientRenderer` per selector.
- `Swiflow.unmount(into:)` — clean teardown for embedded widgets and SPA route transitions.
- Bundle size budget in CI: measure `.wasm` + JS size on every PR; fail if >X% growth without justification.
- Lazy component primitive: `LazyComponent { ... }` boundary backed by JS dynamic import (Phase 11's `LazyRoute` upgrades to use this).
- Component testing harness:
  - `Sources/SwiflowTesting/` module with `render(_:)` → `TestComponent` providing query/click/inputAt helpers.
  - Vitest/RTL-shaped: `try await render(Counter()).click("button").assert(text: "Count: 1")`.
- Macro-driven diagnostics for `@ChildrenBuilder`:
  - A Swift macro that intercepts builder-rejected expressions and emits a specific compiler error pointing at the offender ("returned `String`, expected `VNode` — wrap with `text(...)` or use a tagged element").
  - Optional: a `@Component` macro that eliminates the `final class` + `Component` + `@MainActor` boilerplate for the common case. (Shipped in Phase 13d as `ExtensionMacro`-only — removes `: Component` but **not** `@MainActor`; Swift 6 doesn't propagate isolation retroactively through a macro-emitted extension. Canonical pattern is `@MainActor @Component final class Foo` per Phase 13e correction.)
- 1.0 API surface audit: every `public` symbol gets an `@available(*, introduced: 1.0)` annotation; ABI surface frozen.
- Migration guide: `docs/guides/coming-from-react.md`, `docs/guides/coming-from-vue.md`, `docs/guides/coming-from-swiftui.md`.
- Status line: "Phase 13 (Maturity & 1.0 Readiness)".

**Phase 13 graduates Swiflow to 1.0.**

---

## Post-1.0 punch-list (NOT scheduled in this plan)

Items deferred because they're vertical/ecosystem decisions, not framework primitives:

- First-party data fetching / Suspense — TanStack-Query-shaped (years of design work; punt until the 1.0 surface stabilizes).
- SSR / hydration.
- Service-worker / offline support.
- A11y audit + ARIA-first DSL helpers.
- I18n primitives beyond `@Environment(\.locale)`.
- Drag-and-drop / gesture primitives.
- Visual regression test integration (Chromatic-shaped).

---

## Critical files reference (touchpoints across all 8 phases)

| File | Phases touched | Why |
|---|---|---|
| `Sources/Swiflow/DSL/Modifiers.swift` | 6, 7, 12 | Fix `attr` Bool; add binding modifiers; scoped CSS modifiers |
| `Sources/Swiflow/DSL/VNodeModifiers.swift` | 6, 7, 12 | Same as above (postfix shape) |
| `Sources/Swiflow/DSL/ComponentDSL.swift` | 6 | Loudify `embed { }` contract |
| `Sources/Swiflow/Reactivity/State.swift` | 7 | Binding consumer wiring |
| `Sources/Swiflow/Reactivity/Ref.swift` | 7 (new) | First-party `Ref<Element>` |
| `Sources/Swiflow/Reactivity/Component.swift` | 8, 10 | HMR state migration hook; `onChange(of:)`, `task { }` |
| `Sources/Swiflow/Reactivity/Environment.swift` | 10 (new) | `@Environment` + `EnvironmentValues` |
| `Sources/SwiflowWeb/SwiflowWeb.swift` | 8, 13 | `hmrSwap` entry point; lift single-root trap |
| `Sources/SwiflowWeb/AttributeModifiers.swift` | 7, 12 | Binding/Ref runtime wiring; animation modifiers |
| `Sources/SwiflowWeb/DevAPI.swift` | 9 (new) | `window.__swiflow__` inspector |
| `Sources/SwiflowCLI/DevServer/` | 8 | HMR broadcast pipeline |
| `Sources/SwiflowCLI/Templates/Templates.swift` | 6, 7 | `final class` comment; Binding/Ref demo |
| `js-driver/swiflow-driver.js` | 8 | WASM hot-swap consumer (mirror in `EmbeddedDriver.swift` per `project-js-driver-embedded-sync` memory) |
| `Sources/SwiflowRouter/` | 11 (new module) | Router product target |
| `Sources/SwiflowTesting/` | 13 (new module) | Component testing harness |
| `Package.swift` | 11, 13 | New product targets |
| `README.md` | 6, 8 | Status line + honest perf section |

---

## Verification (per-phase exit criteria)

Each phase exits when:

1. **All findings listed in its scope are demonstrably addressed** — verified by a checkbox audit against this master plan during the phase's `superpowers:finishing-a-development-branch` step.
2. **The Counter template (and `examples/HelloWorld`) exercises the new capabilities** — phase doesn't ship without a user-visible demo.
3. **Test suite passes 100%** — Phase 5's `281/59` baseline grows by N tests with no regressions.
4. **README status line is updated** to name the current phase as latest completed.
5. **`docs/superpowers/specs/2026-MM-DD-swiflow-phase{N}-{name}-design.md`** spec exists and is committed.
6. **`docs/superpowers/plans/2026-MM-DD-swiflow-phase{N}-{name}.md`** plan exists with checkbox steps and is committed before subagent-driven-development kicks off.

For Phase 8 specifically, additional exit criterion: **measured `save → pixels` time on the Counter template is under 1 second, with `@State` preserved across the swap**, recorded in `docs/perf/2026-MM-DD-hmr-baseline.md`.

---

## Per-phase execution flow (same as Phase 5)

1. Run `superpowers:brainstorming` → produce `docs/superpowers/specs/...-design.md`.
2. Run `superpowers:writing-plans` → produce `docs/superpowers/plans/...-plan.md` with checkbox tasks.
3. Run `superpowers:subagent-driven-development` → dispatch implementer + spec-reviewer + code-quality-reviewer per task.
4. Run `superpowers:finishing-a-development-branch` → verify tests, push to `origin/main` (per `user-swiflow-role-and-taste`).
5. Update `MEMORY.md` index with any new project-level conventions learned.

The same conventions from Phase 5 apply:
- Cross-module visibility uses `package`, not `internal` (`project-two-module-package-access`).
- Edits to `js-driver/swiflow-driver.js` must mirror in `EmbeddedDriver.swift` (`project-js-driver-embedded-sync`).
- Treat SourceKit "Cannot find X in scope" reminders as stale until `swift build` confirms (`feedback-sourcekit-diagnostics-are-stale`).

---

## Summary table

| Phase | Name | Motto leverage | Findings closed |
|---|---|---|---|
| 6 | Trust & Polish | Foundation | `.attr` no-op; Binding ship-or-hide decision; `final class` template; README honesty; `embed { }` docs; Phase 2b.3 cosmetics |
| 7 | Bindings, Refs & Form Foundations | Foundation | Binding consumer; Refs; forms recipe; `EventInfo` polish |
| **8** | **HMR & The Instant Dev Loop** | **🎯 Motto centerpiece** | Full-reload→hot-swap; state preservation; dev-mode multi-root; cold/warm rebuild perf; debugger story |
| 9 | Devtools — Component Inspector | Builds on HMR | `window.__swiflow__`; tree walker; state inspector; perf HUD |
| 10 | Effects, Context & @Environment | Day-to-day DX | `onChange(of:)`; `task { }`; `@Environment` |
| 11 | SwiflowRouter | Multi-page apps | Router; Link; route params; nested routes; lazy routes |
| 12 | Styling, Animation & Forms | Polish | Scoped CSS; transitions; CSS-vars bridge; form validation |
| 13 | Maturity & 1.0 Readiness | 1.0 ship | Multi-root lift; lazy components; testing harness; macro diagnostics; 1.0 surface freeze; migration guides |

**Phase 13 ships Swiflow 1.0.**
