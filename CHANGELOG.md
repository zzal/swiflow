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

## [Unreleased]

### Changed

- **Renamed two library modules** for clearer intent (no API surface change —
  only the module names). Dependent projects must update `import` lines and
  `.product(name:)` references:
  - `SwiflowHTTP` → **`SwiflowFetcher`** — the JSON-over-`fetch` client.
  - `SwiflowWeb` → **`SwiflowDOM`** — the WASM/DOM renderer.

  `swiflow init` templates and all bundled examples now use the new names.

---

## [0.1.5] — 2026-06-08

Consolidates Phases 18–21 and the data-layer / UI / tooling work that landed
after `v0.1.3` into a single release (the interim `0.1.4` was a code-level
version bump only, never tagged). New API surfaces — `SwiflowQuery`,
mutations, `.task`, `SwiflowUI` — are **Experimental**; see Stability.

### Added

**Data layer — `SwiflowQuery` (Phase 21)**
- **`SwiflowQuery` module** — a TanStack-Query / SWR-style data layer. A `Query`
  is a `@MainActor` value that knows how to fetch itself and where it lives in a
  shared cache: `associatedtype Value: Equatable & Sendable`, `var queryKey:
  QueryKey`, `var tags: Set<QueryTag>` (default `[]`), `var staleTime: Duration`
  (default `.zero`), `func fetch() async throws -> Value`.
- **Typed hierarchical keys.** `QueryKey = [QueryKeyComponent]` (`.string` /
  `.int`, both `ExpressibleBy…Literal`, e.g. `["users", .int(id)]`) — cache
  identity *and* dependency; the hierarchy enables prefix invalidation.
- **`query(_:)` consumption** — a `Component` method returning `QueryState<Value>`
  (`data` / `error` / `isLoading` / `isFetching` / `isSuccess`). Subscribes the
  component to the cache; a fetch is triggered only by mount, key change, or
  `invalidate` — not on every render.
- **Shared `QueryClient` cache** with request **deduplication** (concurrent
  subscribers to one key share a single in-flight `fetch()`) and
  **stale-while-revalidate** (`staleTime` `.zero` revalidates on every trigger;
  cached data renders instantly while the refetch runs, with `isFetching`
  tracking the background load). Installed automatically per render root by
  `Swiflow.render(into:)`.
- **Invalidation** — `client.invalidate(_ key:, exact:)` (prefix cascade by
  default; exact single-entry with `exact: true`) and `client.invalidate(tag:)`
  for cross-cutting tag groups. Invalidated entries with live subscribers
  refetch immediately.
- **Mutations** — `@MutationState` peer macro (synthesizes a `$name` handle +
  backing runtime, wired in `@Component`'s `bind()` at mount) and the `Mutation`
  protocol (`perform` + `optimistic` + `invalidations`). Optimistic edits apply
  **synchronously**, **roll back** automatically on failure, and fan out
  invalidations on success. Backed by `MutationRuntime` (run → `Result`) and a
  token-keyed mutation task registry.
- **Background revalidation** — opt-in `refetchInterval`, `refetchOnFocus`, and
  `retry` on the `Query` protocol. Clock-driven polling via `tick(now:)`,
  window-focus refetch of stale queries (dedup-safe, reads `visibilityState`),
  and failed-fetch **retry with result-clamped exponential backoff**
  (`RetryPolicy`). Wired in `SwiflowWeb` via a `setInterval` tick + focus
  listener; retry cycles clear on supersede (invalidate / `setQueryData`).
- **Deterministic testing.** `AsyncTestHarness(component, queryClient:
  QueryClient(clock: ManualClock()))` with `settle()` / `flush()` / `advance(by:)`
  / `focus()` drive fetches, polling, and focus refetch to a fixed point with no
  wall-clock dependence.

**Reactivity — async effects (Phase 20)**
- **`.task { … }` / `.task(rerunOn: someEquatable) { … }`** — postfix `VNode`
  modifiers for lifecycle-bound async effects. A bare `.task` runs once on mount
  and cancels on unmount; `.task(rerunOn:)` cancels and restarts when the
  dependency changes (`!=`). Closure: `TaskBody = @MainActor @Sendable () async ->
  Void`. A DEBUG `swiflowDiagnostic` flags stable-slot violations (task count
  changing between renders).
- **Correct-by-default cancellation — superseded/dead-task write guard.** Each
  task is stamped with a `@TaskLocal` `(slotID, generation)` token; `@State`'s
  generated `didSet` reverts writes from a superseded or unmounted task. Stale
  data can neither re-render nor clobber state — no `Task.isCancelled` checks or
  `catch is CancellationError` needed at call sites.
- **`JavaScriptEventLoop.installGlobalExecutor()`** is now wired into
  `Swiflow.render(into:)` (once, idempotently) — without it, `Task`/`await`
  silently hangs in the browser.

**Component DevTools — Chrome panel (Phases 19 + 19b)**
- Chrome DevTools extension at `devtools/` (sideload via `chrome://extensions` →
  Load unpacked). Adds a "Swiflow" tab showing the live component tree and
  `@State` of any Swiflow app in dev mode. Read-only MVP.
- **Live updates** — the panel auto-refreshes within ~250 ms of every render by
  polling `window.__swiflow.perf()` while visible; a footer dot shows status
  (green = live, grey = paused, red = poll failed). Zero Swift changes — it polls
  the Phase 9 render counter. Manual ↻ Refresh remains as a fallback.
- Ships bundled Chromium-derived design tokens (`devtools/colors.css`,
  `devtools/application_tokens.css`) so the panel follows the host DevTools
  theme, including dark mode.

**UI & styling**
- **`SwiflowUI` (v0)** — a layout primitive module: `Spacing` / `CrossAlign` /
  `MainAlign` tokens, a base token sheet with lazy-once `installBaseStyles`,
  `VStack` / `HStack` flex primitives (inline token vars), and chainable
  `.padding` / `.gap` modifiers. Built on a new host-testable
  `StyleInjectionRegistry` once-injection seam (`CSSInjector` now routes through
  it) and a public `element(_:attributes:children:)` array factory.
- **CSS DSL — `host { … }`** (emits `.swiflow-T { … }`, single selector),
  **`raw(_:)`** (verbatim escape hatch for at-rules the DSL doesn't model, e.g.
  `@property`), and scoped at-rule primitives **`container(_:)` / `media(_:)` /
  `startingStyle`** (wrap nested rules in `@container` / `@media` /
  `@starting-style` while still scoping them, via a new `CSSEntry.group` case).
- **`CSSSheet.+` operator** — concatenate sheets so components can split styles
  across files: `static var scopedStyles = layout + theme + animations`. Zero
  runtime cost.
- **CSS declaration helpers** — `outline`, `outlineOffset`, sheet-level
  `cssVar(_:_:)`, plus `positionAnchor`, `positionArea`, `anchorName`,
  `viewTransitionName`, `interpolateSize`, `accentColor`, `colorScheme`,
  `inset`/`insetBlockEnd`/`insetInline`, `placeItems`/`placeContent`,
  `marginInline`, `backdropFilter`, `transitionBehavior`, `containerType`,
  `background` (shorthand), `pointerEvents`, `flex`, `flexWrap`, `listStyle`.
- **Element factories** — `dialog`, `details`, `summary`, `aside`, `output`,
  `hr` (same `(_ attributes:, @ChildrenBuilder children:)` shape; `summary` and
  `output` ship text-only overloads). Popover is `.attr("popover", …)` on any
  element, not a factory.
- **`SwiflowWeb.after(_:do:)`** — cancellable `setTimeout` wrapper returning a
  `TimerHandle` (use from `onAppear`, cancel from `onDisappear`).

**HTTP**
- **`SwiflowHTTP` module** — a small HTTP client, graduated out of TodoCRUD's
  `Net.swift`.

**CLI & dev tooling**
- **`swiflow init --template <name>`** — scaffold from any example under
  `examples/` (`HelloWorld` default, `MiniRouter`, `AsyncFetch`, `QueryDemo`,
  `TodoCRUD`, `EdgeCases`, `SwiflowUIDemo`). `swiflow init --help` lists names
  dynamically. The embedded set is codegen'd from `examples/*/` by
  `scripts/embed-templates.swift` → `Sources/SwiflowCLI/EmbeddedTemplates.swift`,
  with a freshness test that fails the build on drift.
- **Much faster `swiflow dev` rebuilds (~12 s → ~1.6 s).** Two levers: the loop
  first stopped re-running `swift package js` per save (plain `swift build` +
  wasm copy, reusing the JS glue), then a compiler-bypass loop that captures the
  `swiftc` compile + `clang` link from one verbose build and **replays them
  directly**, with a `StalenessKey` (file set + import hash + manifest mtimes)
  deciding replay-vs-recapture. The replayed link injects PackageToJS's
  reactor-ABI flags so the served wasm runs in the browser.

**Examples**
- **AsyncFetch** (`.task(rerunOn:)` demo), **QueryDemo** (cached/deduped/SWR
  fetch + optimistic-rename mutation + invalidate), **TodoCRUD** (`SwiflowQuery`
  over a real Dockerized CRUD API, focus-refetch + 5 s polling), **EdgeCases**
  (12-trap reconciliation stress harness — all traps pass, no reconciler bugs),
  **SwiflowUIDemo**, and **MiniRouter** (richer router demo, replaces RouterDemo).

**Guides**
- `docs/guides/query.md` and `docs/guides/async-tasks.md`.

### Changed
- **`onChange` / `onAppear` lifecycle (Phase 18) — behavior change.**
  `Component.onChange()` now fires on **every** component in the tree after each
  re-render, not just the root (the prior root-only behavior was a bug; React
  `componentDidUpdate` semantics). `Component.onAppear()` now also fires on
  components mounted **mid-render** (revealed by a conditional flip or appended
  to a list during a re-render), which it previously skipped. Internals:
  `collectComponentIDs(_:)` + `firePostRenderLifecycle(_:preExistingIDs:)`
  partition reused (→ `onChange`) vs freshly mounted (→ `onAppear`); no public
  API, JS-driver, or patch-protocol changes.
- `examples/RouterDemo` removed; `examples/MiniRouter` (richer page set, `Back`
  via `router.back`) is the canonical router example. Playwright configs/specs
  and the READMEs swept to scaffold via `--template MiniRouter`.
- **`examples/HelloWorld` rebuilt as a modern HTML/CSS showcase** — split into 8
  focused files, wiring native `<dialog>` (focus trap, `Escape`-to-close, blurred
  `::backdrop`, CSS-only open/close animation via `@starting-style` +
  `allow-discrete`), declarative popovers via `popovertarget` (toast + About card,
  the latter CSS-anchored), a `<details>` inspector with `interpolate-size`, a
  `color-mix` + `light-dark` + `@property --accent` token system that auto-themes
  from the OS, container queries, and `:focus-visible` outlines. `index.html`
  stripped to the loading indicator + minimal body reset.
- DevTools state-pane `@State` rows are now sorted alphabetically (was Swift
  dictionary order, which shuffled between refreshes).
- `TemplateEmbedder.blacklist` now includes `.swiftpm` so codegen ignores
  Xcode-generated user-state files.

### Fixed
- **Release builds: dead event handlers.** `.on(.click)` buttons were inert in
  `swiflow build` (fine in `swiflow dev`). `Event.domName` derived names via
  `String(describing: self)`, which release's `-disable-reflection-metadata`
  collapses to the enum's *type* name `"Event"` — so listeners bound to a DOM
  event that never fires. Replaced with an exhaustive, reflection-free `switch`.
- **HMR no longer blanks the page on hot-swap** — the wasm is re-instantiated on
  each swap (importing the new entry only re-`export`s `init()`; it must be
  re-run with the preserved `@State` snapshot).
- **Stable child slots — conditional/looped children no longer corrupt
  siblings.** Each view-builder statement is now one stable child slot:
  `if`/`else`/`for` compile to a single transparent `.fragment` that holds its
  position even when empty, so a conditional rendered before a stateful sibling
  (e.g. a `<dialog>`) no longer shifts indices and recreates it on unmount. Rule:
  *every statement is a stable slot; key your `for` items.* DOM placement routes
  through three pure primitives (`firstDOMHandle` / `nextDOMAnchor` /
  `collectDOMRoots`); no new patch type, no JS-driver change. ⚠️ Mount-path note:
  because `if`/`for` now nest one level deeper, paths shift (`"3"` → `"3.0"`), so
  an HMR session spanning this upgrade re-mounts affected components once.
- **CSS scoping on the component root** — class-leading scoped rules (e.g.
  `rule(".card") { … }`) now emit a dual selector (`.swiflow-T.card, .swiflow-T
  .card`) so they match the component root *and* descendants (previously the
  descendant-only form silently no-op'd against the root). Edge case:
  comma-separated selector lists only get the dual treatment on the first token
  (`// TODO`).
- **Sign In dialog no longer flickers shut on open** — replaced an interrupted
  `document.startViewTransition` (which could leave the top-layer `<dialog>`
  hidden while `open` and raised unhandled `AbortError`s) with a CSS-only
  animation (`@starting-style` + `transition-behavior: allow-discrete`);
  open/close is now synchronous and gesture-immediate.
- **CI green on Swift 6.3.2.** Keyed the SwiftPM build cache on the tracked
  `Package.swift` (the gitignored `Package.resolved` hashed to empty), so the
  Linux job warms its cache once green and dropped **~13 min → ~4 min**; fixed a
  test-helper infinite recursion that crashed the suite with signal 11; and
  hardened `ProcessRunner` to drain stdout/stderr on dedicated threads
  (deadlock-proof under load).

### Stability
- **Experimental — interfaces may change before 1.0:** `SwiflowQuery`, mutations
  (`@MutationState` / `Mutation`), `.task` / `.task(rerunOn:)`, and `SwiflowUI`.
- The rest is stable for pre-1.0 usage. `--template` is additive (`swiflow init
  my-app` with no flags still produces the HelloWorld scaffold). **Behavior
  change:** `onChange()` now fires on every component and `onAppear()` on
  mid-render mounts (Phase 18) — most code is unaffected; see the mount-path note
  under Fixed for the one-time HMR re-mount across this upgrade.

---

## [v0.1.3] — 2026-05-27

**First public GitHub release.** Tags the Phase 16 + Phase 17 work as
[v0.1.3](https://github.com/zzal/swiflow/releases/tag/v0.1.3) and flips
`swiflow init` so users can scaffold a project without local-path
workarounds: the generated `Package.swift` now pins to the matching
Swiflow release on github.com/zzal/swiflow.

### Changed
- `swiflow init my-app` no longer requires `--swiflow-source`. With no
  flags it generates a versioned URL dep on the official repo pinned to
  the CLI's own version (read from a new `SwiflowVersion.current`
  constant — single source of truth for `--version` and the init
  default). `--swiflow-source` is preserved as the "hacking on Swiflow
  itself" escape hatch; `--swiflow-version <v>` still lets users pin
  to any other published tag.
- `SwiflowDep.officialRepositoryURL` flipped from the pre-release
  placeholder `swiflow/swiflow` to the real `zzal/swiflow`. The
  scaffolded `Package.swift` line now reads
  `.package(url: "https://github.com/zzal/swiflow.git", exact: "<version>")`.
- Empty `--swiflow-source ""` / `SWIFLOW_SOURCE=` (the shell idiom for
  "clear an inherited env var") is now treated as unset. The previous
  behavior silently generated `.package(path: "")` in user code.

### Added
- `Sources/SwiflowCLI/SwiflowVersion.swift` — single-source-of-truth
  constant for the CLI's semver. Bumped in lockstep with each GitHub
  release tag.

### Stability
- This release establishes versioned distribution. Future bug-fix
  releases will land as `v0.1.x` tags; behaviour changes that ripple
  through user code will be called out in the Stability section of the
  corresponding Phase entry.

---

## [Phase 17] — 2026-05-27

**Lifecycle + DOM sync.** Two latent bugs that the Playwright router
suite finally exposed: nested-component `onAppear` fires now (was
root-only since the hook was introduced), and the diff syncs the DOM
when a component swaps element types between frames (was previously
updating the mount tree but leaving the DOM untouched, so routes /
conditional UIs silently appeared frozen). No user-visible API changes;
existing code that used `onAppear` on a non-root component just starts
working, and any code that relied on the previous root-only behavior
already had no body to depend on. CI also unblocked — first green
build since 2026-05-26.

### Changed
- `Sources/SwiflowWeb/Renderer.swift` first-mount path now calls a new
  `fireOnAppearTree(_:)` helper instead of `root.instance.onAppear()`.
  The helper walks the mount tree children-first and fires `onAppear`
  on every component anchor — matching React's `componentDidMount` and
  SwiftUI's `.onAppear` ordering (a parent's hook sees its fully-mounted
  subtree). Symmetric inverse of `destroy()`'s parent-first walk.
- `Sources/Swiflow/Diff/Diff.swift` component-reuse and
  environment-override update arms now splice
  `removeChild`/`appendChild` patches around the recursive update when
  the body's DOM identity changes. A new `domAncestorHandle(_:)` helper
  walks up `mounted.parent` past structural anchors to the first
  DOM-tracked ancestor; for the root-level case (anchors all the way
  up) the Renderer emits a new `replaceMount(selector, newHandle)`
  patch instead.
- `examples/RouterDemo/index.html` dropped its inline
  `<script type="module">` block that called PackageToJS `init()` a
  second time. The driver script's IIFE handles init by itself; the
  manual block was leftover from the pre-13e template migration and
  was double-mounting RouterRoot into `#app`. HelloWorld's template
  had the same fix applied earlier.
- `Tests/playwright/router.spec.ts` Back-button test now navigates to
  `/` and clicks the in-app Link to reach `/#/about` before testing
  Back — the previous version used `page.goto("/#/about")` directly,
  which left no in-app history, so `window.history.back()` took the
  page out of the app.

### Added
- `Patch.replaceMount(selector: String, newHandle: Int)` opcode +
  matching JS-driver handler. The driver tracks the currently-attached
  root **Node reference** per selector (not handle) so the swap works
  even if a preceding `destroyNode` has evicted the old root's handle
  from the `nodes` map.
- Two `node:test` cases in `js-driver/test/opcodes.test.js` covering
  `replaceMount`'s happy path and the missing-selector error.
- Three host-side tests in `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`:
  `OnAppearTreeWalkTests` (children-first ordering), and
  `ComponentTypeSwapTests` covering both the element-child path
  (already handled by `IndexedChildrenDiff`, now regression-guarded)
  and the env-override body path (new).
- Per-suite Playwright configs (`playwright.counter.config.ts`,
  `playwright.router.config.ts`) + `npm run test:counter` / `test:router`
  scripts that spin up only the dev server their spec needs. Cuts
  local iteration time from ~20 min (full `npm test`) to ~1 min per
  suite. `Tests/playwright/README.md` documents the split.
- `Tests/playwright/progress.spec.ts` fix: the `MutationObserver` is
  now installed only after `<html>` is parsed. The previous version
  called `obs.observe(html, ...)` from within `page.addInitScript`,
  which runs BEFORE the HTML parser produces `documentElement`, so
  the observe call threw silently and no progress events were ever
  captured. With the fix, the test reliably sees the driver's
  `data-swiflow-progress` writes.

### Fixed (CI)
- `Sources/SwiflowCLI/Project/BundleManifest.swift` switched from a
  bare `import CryptoKit` (Apple-only) to a `#if canImport(CryptoKit)`
  / `#else import Crypto` pair. The Linux `Test (ubuntu-22.04)` job
  had failed at "Build library + WebTarget" with `no such module
  'CryptoKit'` since Phase 14b Track 1's manifest landed
  (commit bbd9a95, 2026-05-26). `swift-crypto`'s `Crypto` module
  exposes an API-compatible `SHA256`; it was already a transitive
  dependency via hummingbird / swift-certificates, so the fix is
  a one-line conditional import plus declaring the edge explicitly
  on `SwiflowCLI` in `Package.swift`.
- `js-driver/test/progress.test.js` setupDriver now passes
  `url: "http://localhost:3000/"` to its JSDOM ctor. Without it the
  document had an opaque origin (`about:blank`), and the
  `Object.assign(globalThis, window)` line below tripped jsdom's
  `localStorage` getter (which rejects on opaque origins) on Node 20.
  Local Node 24 happened to swallow the throw; the CI's pinned Node 20
  surfaced it as a hard test failure.

### CLI version
- `swiflow --version` reports `0.1.3` (was `0.1.1`). Rolls Phase 16
  and Phase 17 forward to a single release point.

### Stability
- Stable for pre-1.0 usage. No user-facing API changes — components
  that already used `onAppear`, lifecycle hooks, the router, or
  conditional rendering by component type all keep working; the
  difference is that the latter two now behave correctly past the
  initial mount.

---

## [Phase 16] — 2026-05-27

**Foundation-free runtime.** The Swiflow runtime modules (`Swiflow`,
`SwiflowRouter`, `SwiflowWeb`) no longer import Foundation. A new CI
guard prevents reintroduction. No user-visible API changes; query
percent-decoding semantics are byte-for-byte identical to the prior
Foundation-backed implementation.

### Changed
- `Sources/SwiflowRouter/Core/RouteMatching.swift` `splitQuery(_:)` now
  decodes URL query keys and values via a private file-local
  `percentDecode(_:)` helper instead of `String.removingPercentEncoding`.
  Returns `nil` on malformed `%XX` or invalid UTF-8 — same semantics as
  Foundation. The `?? original` fallback in the call sites preserves
  prior behavior on invalid input. UTF-8 validation uses
  `Unicode.UTF8.ForwardParser` (stdlib, no platform gate).
- `Sources/SwiflowWeb/HMR/HMRBridge.swift` dropped its vestigial
  `import Foundation`.

### Added
- `.github/workflows/ci.yml` gains a `Verify Foundation-free runtime`
  step in the `test` job. Greps for `^import Foundation$` in the three
  runtime module roots; fails the build on any hit. Runs before the
  cache restore so violations fail in sub-second wall time.
- 8 regression-guard tests in `Tests/SwiflowRouterTests/RouteMatchingTests.swift`
  pinning percent-decoding semantics (ASCII space, multi-byte UTF-8,
  encoded '+', lowercase hex, encoded key, fallback on lone '%' / bad
  hex, and the deliberate RFC 3986 choice to leave literal '+' as '+').

### Bundle
- Total gzipped: 1,808,783 → 1,808,650 bytes (−133 bytes / −0.0074%).
  The win in this phase is architectural, not size — Phase 15 already
  drained Foundation's transitive cost.

### Stability
- Stable for pre-1.0 usage. No user-facing breaking changes.

---

## [Phase 15] — 2026-05-26

**The dependency diet.** Release bundle gzipped: 18.17 MB → 1.81 MB
(−90.05%). User-facing API is essentially unchanged — `@MainActor
@Component final class Foo`, `@State var count: Int = 0`, `$count`,
forms, router, SwiflowTesting all work identically — with one small
breaking change noted below.

### Changed
- `@State` is now an attached macro (accessor `didSet` + peer
  `$`-projection) instead of a `final class State<Value>` property
  wrapper. State lives inline on the component class; the setter
  routes through a synthesized `didSet` that calls
  `scheduler.markDirty(owner)`. The previous `State<T>`, `Box<T>`,
  and `StateWireable` protocol are deleted.
- `@Component` macro now also a `MemberMacro`: scans the class body
  for `@State`-decorated members and emits `_ComponentRuntime`
  conformance — a static `stateCells: [any AnyStateCell]` array, a
  `bind(owner:scheduler:)` method, and private `runtimeOwner` /
  `runtimeScheduler` storage. The framework iterates `stateCells`
  instead of walking `Mirror.children`.
- `HMRBridge.encodeStateMap` and `DevAPI.encodeStateForDisplay`
  dropped their `Mirror.displayStyle` Optional-detection paths.
  Task 5's macro normalizes Optional `.none` to `HMRNilSentinel` at
  the source, so the encoders dispatch on the sentinel.
- Release builds compile with `-Xswiftc -disable-reflection-metadata`.

### Added
- `_ComponentRuntime: Component` sub-protocol — the opt-in adoption
  point for the framework-runtime members the `@Component` macro
  emits. Hand-rolled `Component` conformances skip it (correct
  default for code outside the macro's contract).
- `AnyStateCell` protocol + `StateCell<Owner>` generic struct in
  `Sources/Swiflow/Reactivity/StateCell.swift`. Macro-emitted closures
  receive `Owner` directly with no `as!` casts in expansion output.
- `StateCell` includes an `_hmrCoerce<T>(_:to:)` helper for the
  Int↔Double bridge coercion the JS HMR path needs.
- `HMRNilSentinel` elevated to `public` (it's referenced from
  macro-emitted code in user modules).

### Breaking
- `@State` requires an explicit type annotation. `@State var x = 0`
  no longer compiles; write `@State var x: Int = 0`. The macro
  needs the static type to emit the matching `Binding<T>`
  projection. Migration: add `: Type` to existing `@State`
  declarations. (HelloWorld + project templates updated.)

### Bundle-size impact
- WASM: 46,059,478 → 5,084,775 raw (−88.96%); 18,165,326 → 1,797,205
  gzipped (−90.11%).
- JS runtime unchanged (55,847 raw / 11,578 gzipped).
- Total gzipped: 18,176,904 → 1,808,783 (−90.05%).
- See `docs/perf/2026-05-26-wasm-bundle-audit.md` for the full
  per-step breakdown and the explanation of why the saving exceeded
  the spec's 5% target by 18×.

### Test changes
- Deleted `Tests/SwiflowTests/Reactivity/StateTests.swift` (exercised
  `State<T>` class internals that no longer exist). Coverage of the
  new path lives in `ComponentRuntimeTests.swift`.
- Migrated tests that constructed `State<T>` directly to use a small
  `@MainActor @Component final class` test-host pattern.
- Updated macro test fixtures from `@MacroState` → `@State` after
  the rename in Task 6.

### Migration
- `@Component`-decorated classes: add `: T` to any `@State var x = …`
  declarations missing an explicit type. No other source changes.
- Hand-rolled `Component` conformances: zero changes required.
  `Component`'s requirements are unchanged. To opt into HMR support,
  conform to `_ComponentRuntime` and implement `stateCells` +
  `bind(owner:scheduler:)`.

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
