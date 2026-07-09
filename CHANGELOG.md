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

---

## [0.4.12] — 2026-07-09

**Beta.** The testing & data-fetching release: audit Part VI (SwiflowTesting,
PRs #203–#206) and Part II Wave 3 (SwiflowQuery + SwiflowFetcher, PRs
#207–#210) are both now complete end-to-end.

**Stability:** Stable for pre-1.0 usage. No breaking changes.

### Added

- **Typed URL query parameters** — `query:` overloads take `[String: String]`
  and percent-encode with an owned encoder, so callers stop hand-concatenating
  and hand-escaping URLs.
- **`Encodable` request bodies** — mutation/fetch bodies accept any `Encodable`
  value via a `JSONValue` encoder (JavaScriptKit shipped only a decoder), so
  request payloads are typed rather than hand-built dictionaries.
- **`RetryPolicy` fluency** — `baseDelay`/`maxDelay` default to the standard
  1s-doubling / 30s-cap backoff, so `RetryPolicy(maxRetries: 5)` is enough; a
  `.retries(n)` copy reads fluently off a base policy (`.default.retries(5)`).
- **Testing interaction vocabulary** — strict `fire`/`press` interactions
  (with caller-side `Issue` diagnostics and `IfPresent` opt-outs), `settle()`
  flush-first semantics, and `find(role:label:class:)` returning a live,
  actable `TestNode`.
- **Testing fidelity** — scoped-rerender fidelity, live input snapshots, and
  `advance(by:)` clock threading in the harness, so component tests observe the
  same render/clock behavior production does.

### Fixed

- **`query()` silent-degradation diagnostics** — the three paths where
  `query()` used to fail soft into a perpetual `isLoading` (wrong/absent
  observer, ambient downcast miss) now emit a DEBUG diagnostic instead of
  spinning forever with no explanation.

### Internal

- Testing harness plumbing: shared teardown routine, flush batching, and
  tree-dumping expectation matchers (PR #204).

---

## [0.4.11] — 2026-07-08

**Beta.** The component composition & guardrails release: the remainder of
audit Part V (SwiflowUI + SwiflowColor Waves 2–3, PRs #196–#201) — Part V is
now complete end-to-end.

**Stability:** Stable for pre-1.0 usage. **One breaking change** (below).

### Breaking

- **`DataTable(maxHeight:)` is now a CSS length string** (`"480px"`), not
  `Spacing?` — the old type let `.lg` compile into a nonsensical 1.25rem
  scroll box; only `.custom` was ever sensible. Migrate
  `maxHeight: .custom("480px")` → `maxHeight: "480px"`.

### Added

- **Typed design tokens** — `Token` covers the entire shipped `--sw-*`
  vocabulary: `.style("background", .surface)` fails at compile time where
  a stringly `var(--sw-surfce)` typo failed silent. `Theme` overrides route
  through the same constants (`ThemeToken.set(.warning, "#b45309")`), so the
  read and write vocabularies cannot drift — and a CI test pins the
  vocabulary to the shipped sheet.
- **Stringly `.style` values are validated too** — DEBUG builds scan
  `var(--sw-…)` references in string style values against the token
  vocabulary and warn on unknown names (composites and app-custom
  properties keep working untouched).
- **`Card(variant: .plain)`** — the bare padded surface (background +
  radius + padding, no shadow or border).
- **Button builder labels** — `Button(variant: .danger, action: { … }) {
  trashIcon(); text("Delete") }`, the overload slot reserved since M4; a
  form-button twin covers `type: .submit`. Icon-only labels without an
  `aria-label` warn in DEBUG (no accessible name).
- **Alert/Prompt content is live** — `title`/`message`/actions/button
  titles now update on every parent re-render; the "captured at first
  presentation" caveat (and its `key:` workaround) is gone.
- **Stale-embed detection** — components whose init content freezes at
  first mount (DataTable rows, sync Autocomplete options) now carry a
  content digest; DEBUG builds warn when the content changes under an
  unchanged key with no `refresh:`, instead of silently showing
  first-mount data. App embeds can opt in via `embed(contentKey:)`.

### Fixed

- **DataTable virtualization is wasm32-safe** — scroll/runway pixel math
  computed in `Double` and clamped: an extreme scroll position or a
  runway past 2³¹ px can no longer trap the wasm module (the 32-bit `Int`
  class of bug; host tests now pin the exact clamping wasm gets).

### Internal

- One authoring site for the overlay entry/exit animation quartet
  (Dropdown/Autocomplete/dialog chrome interpolate a shared generator —
  the third copy had already drifted its load-bearing comment).
- Autocomplete's state transitions and Dropdown's roving-focus decision
  table promoted to host-testable seams (the pure roving table is
  unit-pinned for the first time).
- `swiflowcolor.md` documents the runtime flip side of native-only: no
  runtime contrast checking exists — dynamically-themed palettes must be
  validated at generation time.

---

## [0.4.10] — 2026-07-08

**Beta.** The store hardening & UI polish release: audit Part IV Wave 3
(SwiflowStore hardening + router guardrails, PRs #184–#187), all of Part V
Wave 1 (SwiflowUI + SwiflowColor, #188–#192), and Part V Wave 2's first two
structural items (#193–#194) — 11 reviewed PRs.

**Stability:** Stable for pre-1.0 usage.

### Added

- **`StoreKey<Value>`** — typed storage keys: name + value type in one
  declaration (`StoreKey<[City]>("pinned-cities")`), so the type can't
  drift between the save site and the load sites; `store.load(key)` infers,
  `save(_:for:)` type-checks. On the `PersistedStorage` protocol, so test
  doubles share the surface.
- **Router DEBUG guardrails** — three silent-misuse shapes now warn (never
  crash): a sibling route shadowed by an earlier same-shape pattern
  (`/users/:id` then `/users/:slug` — first match wins, the second is
  dead) or by a non-last catch-all; an empty `:` segment; and navigation
  matching no route (logged once per path, naming it). All compile to
  nothing in release.
- **`Button(variant: .danger)`** — a destructive solid fill on a complete
  danger token family: `--sw-danger-hover`/`-active` derive from
  `--sw-danger` exactly like the accent family (re-point one token, the
  palette cascades), `--sw-danger-text` is `contrast-color()` with
  WCAG-proven fallbacks in both modes.
- **`$toasts.show("Saved!", .success)`** — firing a toast is one call;
  the `send(.show(ToastItem(...)))` longhand remains for pre-built items.
- **RadioGroup name-collision detection** — two same-label groups slug to
  one native radio `name` and silently share selection/arrow-roving at the
  DOM level; DEBUG builds now detect this via an invisible mount sentinel
  and warn naming both groups and the explicit-`name:` fix.
- **DataTable duplicate-column warning** — `Column.id` defaults to the
  title, so same-titled columns silently shared sort identity; DEBUG now
  says so at construction.

### Fixed

- **DataTable misconfiguration no longer crashes DEBUG builds** — the
  three sites whose docs promise "falls back to a non-virtualized render"
  (missing `maxHeight`, non-positive `rowHeight`, the columnsTemplate+width
  advisory) warned through the *trapping* diagnostic; they now warn and
  fall back exactly as documented.
- **Wide-gamut (P3) rendering can no longer dip below the validated
  contrast bar** — chroma widening at constant OKLCH lightness shifts WCAG
  luminance (the old "same lightness → same contrast" claim was wrong), so
  the theme generator now emits the widest chroma whose whole derived
  family still clears its bars on a P3 display, backing off when needed.
  The shipped base sheet's display-p3 block is now under the same test
  (all values pass).
- **`PersistentStore` survives multi-tab life** — another tab upgrading or
  deleting the database no longer blocks forever on our connection
  (`onversionchange` closes and re-opens lazily), a browser-closed
  connection no longer traps the wasm on the next call (sync IndexedDB
  exceptions surface as thrown `StoreError`s), and failed requests log a
  DEBUG warning (fire-and-forget saves `try?` them away).
- **`Color.hex` shorthand trap** — a raw 3-digit hex like `"f00"` silently
  parsed as near-black `0x000f00` and flowed into contrast validation; it
  now traps per the documented contract, pointing at `normalizeHex`.

### Internal

- `ModalDialogHost` — Alert's and Prompt's byte-identical modal machinery
  (open/close sync, guarded native-close handler, backdrop dismissal, ref,
  scaffold) consolidated into one owned struct before it could drift
  further (the copies' comments already had).
- Registry-backed test suites follow the one-suite-owns-a-global-seam rule
  (`.serialized` is per-suite, not cross-suite — a parallel-test race
  taught this the honest way).

---

## [0.4.9] — 2026-07-08

**Beta.** The router & store DX release: Part IV of the 2026-07 architecture
& DX audit — SwiflowRouter and SwiflowStore — shipped complete (Waves 1 + 2)
as 8 reviewed PRs (#174–#181), plus a docs catch-up (#182) that brings every
guide current, including a new persistence guide.

**Stability:** Stable for pre-1.0 usage.

### Added

- **`@Persisted`** — persistent reactive state with zero ritual:
  `@Persisted var magnitude: String = "2.5"` behaves exactly like `@State`
  (dirty-marking writes, `$name` binding) and additionally hydrates from
  IndexedDB on mount and saves on every write. Keys auto-namespace by the
  owning component's type (`"QuakesPage.magnitude"`); pass
  `@Persisted("legacy-key")` to share or migrate. The old ~8-line ritual
  (store instance, key constants, hydrate task, `onChange` saves) is gone —
  QuakesPage in MissionControl is the worked example. New
  [persistence guide](docs/guides/persistence.md).
- **Typed path params** — `ctx.param("id")` is non-optional (a matched route
  guarantees its declared captures), and `ctx.param("num", as: Int.self)`
  parses through `LosslessStringConvertible`. A typo'd param *name* logs a
  DEBUG warning naming the declared params; an unparseable *value* (URLs are
  user input) is a silent `nil`. The `ctx.params["id"] ?? ""` ritual is
  retired from every example and doc.
- **`Link` active state** — a `Link` whose destination matches the current
  path emits `aria-current="page"` and a `sw-link-active` class.
  `active: .prefix` also lights section links on segment children
  (`/users` on `/users/42`), segment-aware and root-safe.
- **`RouterRoot` `notFound:`** — a custom 404 closure receiving the
  unmatched path, rendered inside the router environment so a `Link` home
  works. The bare diagnostic text remains the default.
- **No-op router warning** — writing `navigate`/`replace`/`back` on the
  default no-op router (the classic read-`@Environment`-outside-`body`
  mistake) now logs a DEBUG warning naming the attempted path and the fix,
  instead of silently doing nothing.

### Fixed

- **Hash navigation no longer depends on a live event listener** — the
  router's path state now commits imperatively in both modes through one
  dedupe-guarded choke point; the browser's echoed `hashchange` is absorbed
  without a second render. Previously a dead listener silently killed hash
  navigation while history mode kept working.
- **One URL convention** — hash-mode push, replace, and `href` all build the
  same canonical `"#/path"` form through one construction site
  (`RouterMode.url(for:)`); push used to write a bare path while the others
  prefixed `#`.
- **`PersistentStore` no longer traps off-browser** — its wasm/host split
  was keyed on `canImport(JavaScriptKit)` (true on host), so constructing a
  store in host tests or tooling aborted at `JSObject.global`. Now keyed on
  `arch(wasm32)`; hosts get the inert stub as documented.

### Internal

- **`Navigator` seam** — RouterRoot's URL machine (location reads, history
  writes, listeners) sits behind a package protocol; `BrowserNavigator` is
  the verbatim JS crossing with guarded, descriptively-fatal globals, and
  the whole routing lifecycle is host-tested for the first time (initial
  read, event wiring, navigate/replace/back, teardown).
- **`RouterMode` owns its behavior** — `changeEvent`/`url(for:)`/
  `readPath(from:)` live on the mode; the five open-coded mode switches are
  gone.
- **`Component._swiflowDidMount`** — a framework mount hook (default no-op,
  fired before `onAppear`) that `@Component` synthesizes when needed; it is
  what `@Persisted` hydration rides.
- **`PersistedStorage` seam** — the store crossing behind `@Persisted`, with
  one shared default `PersistentStore` and a test-swappable registry; the
  full hydrate→render→write→save loop runs headless in CI.
- **`swiflowWarn`** — the framework's first non-trapping warn primitive
  (DEBUG console warning, release no-op), the vehicle for the router's new
  diagnostics.

---

## [0.4.8] — 2026-07-07

**Beta.** The CLI & tooling audit release: Part III of the 2026-07
architecture & DX audit — SwiflowCLI and the macro plugin — shipped complete
(Waves 1 + 2) as 9 reviewed PRs (#164–#172).

**Stability:** Stable for pre-1.0 usage.

### Added

- **Compile errors reach the browser** — a failed `swiflow dev` rebuild now
  broadcasts the compiler output to the page, rendered as a dismissable
  full-viewport overlay (the Vite model): the real diagnostic with source
  context, anchored at the first `error:` line, ANSI-stripped. The next
  successful rebuild clears it. Previously the browser silently kept
  rendering the last-good build with a terminal-only failure line.
- **Cold-build expectations + timings** — `swiflow dev`'s first build on a
  fresh project warns that dependency resolution + WASM compilation can take
  a few minutes (silence used to read as a hang); every initial build ends
  with an elapsed stamp (`built in 13.0s`), and hot swaps report save-to-swap
  latency (`hot-swapped in 0.5s`).
- **Failures route to `swiflow doctor`** — toolchain-plausible `build`/`dev`
  failures now point at doctor, and `swiflow init`'s next steps lead with it,
  so first-timers learn the toolchain check exists *before* the first cryptic
  failure.

### Fixed

- **Doctor agrees with the build** — `swiflow doctor` now probes the
  toolchain through the same code paths `build`/`dev` use: it can no longer
  bless a WASM SDK the build would reject (the filter had diverged), and it
  reports the same compiler binary the build actually runs.
- **`swiflow init`'s copy-paste serve command** no longer chains `open` after
  the foreground server (which blocked it from ever running); the URL is a
  comment instead.
- **Tailored macro diagnostics** — `@MutationState`/`@ReducerState` misuse
  now gets a message matching what you wrote (a `let`, a missing type, a
  computed property, a `didSet`, a tuple pattern) instead of one folded
  "requires a `var` with an explicit type annotation" for everything.
- **Dev-loop status voice** — one action-first voice
  (`rebuilding… / hot-swapped / reloaded / rebuild failed — <reason>`)
  replaces the mixed tense and internal jargon (`HMR broadcast`).

### Internal

- A compiled macro-consumer target now gates emitted macro code in CI —
  public/package access, witness isolation, and init synthesis are verified
  by the real compiler on every push, not just by golden-string tests.
- `SwiftContext` owns the swiftc invocation preamble (executable, project
  cwd, `TOOLCHAINS`) in one place — the drift class behind the old
  command-vs-reactor-ABI incident is structurally closed.
- `swift run swiflow-codegen` replaces the standalone codegen scripts: one
  emit path for the embedded driver/templates, with the per-example
  runtime-JS copies refreshed by tool and enforced by a widened CI gate.
- Rebuild diagnostics are captured on every dev-loop path (the recapture
  path used to discard them entirely, showing nothing but "exit code 1").

---

## [0.4.7] — 2026-07-07

**Beta.** The architecture & DX audit release: the Swiflow/SwiflowDOM core
backlog (Part I) and the entire SwiflowQuery/SwiflowFetcher backlog (Part II)
of the 2026-07 audit, shipped as 21 reviewed PRs (#142–#162).

### Added

- **`embed(_:refresh:)`** — push changed props into a reused embedded
  component without re-keying it (re-keying remounts and destroys `@State`,
  which reuse exists to preserve). `refresh:` runs against the reused instance
  right before its body evaluates; target plain stored properties, not
  `@State`.
- **Typed attribute helpers** — `.href`, `.target`, `.rel`, `.newTab()`
  (sets `target="_blank"` *and* `rel="noopener noreferrer"` together),
  `.src`, `.alt`, `.width`, `.height`, `.placeholder`, `.type(InputType)`,
  `.name`, `.for`, `.title`. `.attr(_:_:)` remains the long-tail escape hatch.
- **Type-referenced invalidation** — `Invalidation.exact(TodoList())` /
  `.prefix(UserQuery(id: id))` take the typed owner of the key, so
  `invalidations` rhymes with `optimistic`'s `.update(TodoList())` instead of
  restating a raw key that a renamed `@Query(prefix:)` would silently orphan.
- **Derived default `invalidations`** — a mutation's `invalidations` now
  defaults to refetching exactly the keys its `optimistic(_:)` declares
  (deduped, in declaration order). Plain optimistic CRUD mutations no longer
  need the boilerplate method, and "optimistic without invalidations" — the
  cache keeping the guess forever — is inexpressible rather than diagnosed.
  New contract: keep `optimistic(_:)` a pure declaration (it is re-read on
  success); run-once effects belong inside the edit's transform closure.
- **Imperative refetch** — `QueryState.refetch()` (the "Refresh" button:
  snapshot carries its client + key, works from event handlers, supersedes
  in-flight fetches) and `Component.invalidate(query:)`/`(key:exact:)`/
  `(tag:)` sugar, handler-safe via a persistent last-rendered-root fallback.
- **`HTTPTransport` seam** — `HTTPClient` now sends through an injectable
  transport (`HTTPRequest`/`HTTPResponse` plain-Swift values; browser default
  `FetchTransport`), making request building, header merge, status mapping,
  and decode policy host-testable with a mock.

### Fixed

- **Silent patch-failure divergence** — a driver-side patch failure used to
  desync the Swift mount tree from the real DOM permanently; the renderer now
  detects it and performs a one-shot resync remount of the affected root.
- **wasm32 clock trap at ~25 days of uptime** — `SystemQueryClock` narrowed
  `performance.now()` through 32-bit `Int`, trapping the whole app once page
  uptime passed `Int32.max` ms. Widened through `Int64` with a non-finite
  clamp.
- **Optimistic rollback could resurrect stale data** — the rollback guard was
  generation-only, so an evicted-then-recycled cache entry (which restarts at
  generation 0) could accept a failed mutation's rollback and have newer data
  clobbered by the previous incarnation's snapshot. Rollback now double-guards
  on entry identity + generation, mirroring `commitFetch`.
- **`onChange(of:)` default keys collided across call sites** — two calls in
  the same `onChange()` override silently shared one storage slot; keys now
  default to `#fileID:#line`.
- **Fragment-rooted bodies at the app root** — the mount path now traps with
  actionable guidance in all build configurations instead of feeding the DOM
  a bogus handle in release.
- **Superseded fetches now abort at the network layer** — cancelling a query
  fetch (invalidate, optimistic write, eviction) aborts the underlying
  browser `fetch` via a per-request `AbortController` instead of letting it
  download to completion; a cancelled exchange surfaces as `CancellationError`,
  never as a transport error a retry policy would chase.
- **Invalidation error policy unified** — invalidating an errored query keeps
  the last error visible until the refetch settles (SWR-symmetric with stale
  data); optimistic writes clear it (the write is the new truth). The two
  paths had drifted apart; they now share one deliberate implementation.

### Examples

- **TodoCRUD / QueryDemo templates modernized** — typed invalidations, then no
  `invalidations` at all (derived defaults); QueryDemo gains a **Refresh**
  button (`state.refetch()`); TodoCRUD's temp-id allocation moved into the
  optimistic transform per the new purity contract.

### Internal

- Core refactors from the audit: shared `reconcileStructuralBody` diff arm,
  `installRenderContext` ambients owner, typed `SwiflowDriver` facade over
  `window.swiflow`, `HandlerRegistry` mutation funnel, unified `JSScalar`
  Swift↔JS crossing, `QueryEntry.supersede` reset contract, and removal of
  the dead `valuesEqual` witness (`select`-style change detection remains the
  reserved door via `Query.Value: Equatable`).
- The CI Playwright pipeline is green end-to-end for the first time (config
  scoping + dedicated per-demo suites + a port-clash fix), and the query
  fuzz model gained eviction/unsubscribe coverage.

---

## [0.4.6] — 2026-07-04

**Beta.**

### Examples

- **MissionControl template refreshed.** A root `Shell` component now owns
  app-wide `scopedStyles` (dogfooding 0.4.5's scoped-styles carrier — its body
  is a bare `embed { RouterRoot { … } }`), with a shared `.page-title`
  treatment and reworked Weather/Quakes page layout. Scaffolded via
  `swiflow init my-app --template MissionControl`.

---

## [0.4.5] — 2026-07-04

**Beta.**

### Fixed

- **`scopedStyles` on a component whose body root is a non-element now works.**
  A `@Component` with `scopedStyles` but a bare `embed { … }` (or fragment)
  body root had its sheet injected yet silently unmatchable — the
  `.swiflow-<Type>` scope class had no element to land on. Such roots are now
  auto-wrapped in a layout-neutral `display: contents` carrier bearing the
  scope class, so app-wide styles owned by a root shell component just work.
  Components without `scopedStyles` keep their exact DOM shape.
- **Navigating routes no longer crashes when the router has a DOM ancestor.**
  A latent double-splice in the diff (both the component and
  `environmentOverride` update arms issued `removeChild`+`appendChild` for
  the same routed-page swap) aborted the patch batch with `NotFoundError`.
  Exposed by the carrier above — any `RouterRoot` nested inside a plain
  element was affected. The splice is now gated on wholesale body-root
  replacement, so exactly one remove/append pair is emitted.

---

## [0.4.4] — 2026-07-04

**Beta.**

### Fixed

- **A `swiflow build` in a project directory no longer poisons later
  `swiflow dev` sessions.** The build's leftover `swiflow-manifest.json` made
  the service worker precache the *build* outputs and serve them cache-first,
  shadowing every dev rebuild — a stale page that survived server restarts.
  Three layers: the service worker treats a missing manifest (404) as "not a
  built site" — install precaches nothing and activate drops every
  `swiflow-*` cache, so **already-poisoned browsers self-heal on their next
  dev visit**; `swiflow dev` deletes a leftover manifest at startup; and the
  dev server refuses to serve the manifest path. Transient manifest failures
  (5xx/network) still keep the previous worker's verified caches serving.

### Examples

- MissionControl's city search now uses SwiflowUI's async
  `Autocomplete(loader:)` — debounce, keystroke cancellation, and
  Searching/error/empty panel states come from the component instead of the
  hand-rolled TextField + results list; committing a suggestion pins the city
  and clears the field in one gesture. Weather toolbar layout polished.

---

## [0.4.3] — 2026-07-03

**Beta.**

### Fixed

- **`.style("--custom-prop", value)` / `.cssVar(...)` silently did nothing.**
  The driver applied inline styles with bracket assignment, which browsers
  ignore for CSS custom properties; `--`-prefixed names now go through
  `style.setProperty(...)` (the remove path already did). This un-breaks the
  dynamic-value pattern the styling and theming guides recommend
  (`.cssVar("--x", value)` + `var(--x)` in the sheet), including scoping
  `--sw-*` token overrides to a subtree.

### Docs

- Guides refreshed against the shipped surface: `@Component` needs no
  explicit `@MainActor` (testing), mutations / focus & interval refetch /
  GC / auto-retry have shipped (query), the `Form`/`Field`/`FormController`
  layer has shipped (forms), `Alert(dismissOnBackdrop:)` exists (SwiflowUI),
  DevTools console API return shapes, and compile-breaking samples in the
  environment and router guides.

---

## [0.4.2] — 2026-07-03

**Beta.** Curates the scaffolding surface ahead of the 0.4 announcement.

### Changed

- **`swiflow init` templates curated to six**: EdgeCases, HelloWorld,
  MissionControl, QueryDemo, SwiflowUIDemo, TodoCRUD. AsyncFetch and
  MiniRouter join RegionDemo as read-only teaching examples — TodoCRUD and
  MissionControl already showcase those concepts in fuller apps.
  `swiflow init --help` and the README now state the curation explicitly,
  and the CLI binary sheds the de-listed embedded templates.

---

## [0.4.1] — 2026-07-03

**Beta.** Patch release for a first-contact scaffolding bug found within hours
of 0.4.0 — thanks to the first bug reporter.

### Fixed

- **`swiflow init <name> --template QueryDemo` (or `AsyncFetch`) produced
  invalid Swift when the project name wasn't a valid identifier** (e.g.
  `my-swiflow` → `final class my-swiflow`). Those templates' root classes are
  renamed (`QueryRoot` / `FetchRoot`), and template codegen now fails loudly
  if any example ever places the project-name token in Swift declaration
  position again (guard in the embedder + the codegen script + an in-suite
  regression test). Project names remain directory-style — hyphens welcome.

---

## [0.4.0] — 2026-07-02

**Beta.** The largest release to date: local reducers, a managed toast queue,
`@Component` without `@MainActor` boilerplate, a scoped re-render engine — and
a full-framework pre-launch audit whose findings are all remediated in this
release.

**Stability: Beta — stable for pre-1.0 usage.** The public surface was
deliberately reviewed and reshaped for this release; breaking changes below
are the result. Expect the API to hold from here barring audit-grade findings.

### Added

- **`@ReducerState` / `Reducer`** — a local, per-component reducer cell for
  app-level client state (wizards, queues, multi-step flows): pure synchronous
  `reduce(into:_:)`, dispatch via `$flow.send(.action)`, effects stay at the
  call site. Modeled 1:1 on `@MutationState`.
- **`ToastQueue` + `ToastStack(queue:)`** — a managed toast queue built on
  `@ReducerState`: at most `maxVisible` toasts (default 3), FIFO overflow
  promotion, and duplicate coalescing into a single toast with a live `×N`
  recurrence badge. The `Binding`-based `ToastStack(toasts:)` is deprecated.
- **`@Component` auto-injects `@MainActor`** — a bare `@Component final class`
  is now isolation-complete; the `@MainActor @Component` boilerplate is gone.
  `nonisolated` on a member opts out. (Members in extensions still annotate
  explicitly.)
- **Scoped re-render + row recycling** — a single-`@State` change re-renders
  only the owning component's subtree; `DataTable`'s virtualized rows are
  memoized and recycled (`.memoKey(_:)` ships as a general diff-bail
  primitive). Moderate drags on a 2,000-row virtualized table now render in
  ≤1 frame. `onChange()` now fires only for components whose subtree actually
  re-rendered.
- **`EventInfo.fromInteractiveDescendant`** — true when a click originated
  inside a link/button/form control between the target and the bound element,
  so container-level click handlers (row/card navigation) can ignore clicks
  aimed at controls inside them. `DataTable.onRowClick` uses it.
- **`RadioGroup` gains `size:`** — matching every sibling form control.
- **Virtualized `DataTable` declares explicit ARIA table roles** — the
  CSS-display overrides can no longer strip implicit table semantics.
- **CLI hardening** — `swiflow init` validates project names (no more
  path-escaping scaffolds); a taken dev-server port prints
  `port 3000 is already in use — pass --port <n>` instead of a raw error;
  served files are symlink-canonicalized against the project root.
- **Region decode diagnostics** — a host/guest schema mismatch now diagnoses
  in DEBUG instead of a handler silently never firing.

### Changed

- **Breaking:** the CSS builder's 72 property free functions (`color(_:)`,
  `padding(_:)`, …) are now static members of `CSSDeclaration`, and
  `rule`/`host`/`from`/`to`/`at` take them as variadic arguments with
  leading-dot syntax: `rule(".card", .padding("1rem"), .color("var(--sw-text)"))`.
  Frees the module's top-level namespace of single-word names that collided
  with app code; argument position (not a closure) keeps leading-dot lines
  from parsing as postfix continuations of the previous statement. The outer
  `css { }` / `keyframes` / `container` / `media` / `startingStyle` builders
  are unchanged.
- **Breaking:** `HTTPError.status(Int)` is now `HTTPError.status(Int, body:
  String?)` — non-2xx responses carry a best-effort capture of the response
  text instead of discarding it.
- **Breaking:** the `Scheduler` protocol is `@MainActor` (custom schedulers
  must isolate). `RAFScheduler` is no longer public (driver-internal).
- `$`-projections (`$count`, `$flow`, …) now copy the property's declared
  access level, so a `public` component's `@State public var` is bindable
  cross-module.
- `Mutation` handles: `reset()` detaches an in-flight mutation (its late
  completion can no longer resurrect the handle's state; cache effects —
  rollback, invalidations — still run); a mutation that applied optimistic
  edits but declares no invalidations now diagnoses in DEBUG.
- Polling queries are paced by the last **attempt**: after retries exhaust,
  polling resumes one interval after the last failure (previously it refired
  every tick — a retry storm against a down server); a never-succeeded
  polling query now recovers at the interval instead of never.

### Fixed

- Comma-separated selectors in scoped `rule()` lists are now fully scoped —
  everything after the first comma previously leaked as global CSS.
- `DataTable` row clicks no longer fire when the row-select checkbox or an
  in-cell control was the real target.
- Idiomatic multi-binding declarations (`@State var a: Int = 0, b: Int = 0`)
  are rejected with an actionable diagnostic instead of opaque compiler
  errors (also `@MutationState`/`@ReducerState`).
- A user-written `@MainActor func fetch()` on `@Query`/`@Mutation` no longer
  double-stamps ("multiple global actor attributes").
- The wasm event dispatcher and HMR bridge guard all JS-number narrows with
  `Int(exactly:)` — a malformed call from any page script (NaN, a
  timestamp-sized number) can no longer trap the whole app (wasm32 `Int` is
  32-bit).
- A query evicted mid-fetch and recycled can no longer have stale data
  committed over fresh (entry-identity commit guard).
- Fragment-bodied components degrade safely (no phantom DOM handles; DEBUG
  diagnostic recommends wrapping multi-root bodies in one element).
- Per-column `.width` is honored in virtualized `DataTable` grids.
- An optimistic update against a not-yet-loaded query skips silently instead
  of trapping in DEBUG.
- Bare query flags (`?debug`) surface in `RouterContext.query` as empty
  strings instead of being dropped.

---

## [0.3.5] — 2026-06-26

`SwiflowColor` becomes a public library, and `swiflow theme` diagnostics gain a
perceptual (APCA) second opinion.

### Added

- **`SwiflowColor` public theme-generation library.** The contrast-validated color
  engine behind `swiflow theme` now ships as a public `.library` product with a
  curated API: `ThemeGenerator.generate(_:)` takes a `ThemeOptions` (mirroring the
  CLI flags) and returns a `ThemeResult` — the generated CSS plus any contrast
  `failures` (structured, each with a WCAG ratio and advisory APCA reading). Contrast
  shortfalls are **returned, never thrown**; only malformed hex throws
  `ThemeError.invalidHex`. `Contrast.wcag` / `Contrast.apca` expose the hex-based
  contrast metrics. The library is **native-only** (host tooling, build plugins,
  scripts — not the browser). Add `.product(name: "SwiflowColor", package: "Swiflow")`;
  see [`docs/guides/swiflowcolor.md`](docs/guides/swiflowcolor.md).
- **Advisory APCA reading in `swiflow theme` diagnostics.** When a seed fails its WCAG
  bar, the per-token diagnostic now also reports an APCA-W3 perceptual reading — e.g.
  `APCA Lc 68 (suggests ≥ 75 for text)` — as a second opinion. WCAG 2.x remains the
  sole gate; a passing palette prints nothing extra.

**Stability: stable for pre-1.0 usage.**

---

## [0.3.4] — 2026-06-26

SwiflowUI theming: status-color seeds for the `swiflow theme` generator, two new
semantic tokens, wide-gamut output, and `@property`-registered design tokens.

### Added

- **`swiflow theme` status-color seeds.** The palette generator gains `--danger`,
  `--success`, `--warning`, and `--info` flags that emit brand status colors into
  the generated `:root`. Each is WCAG-validated for how its token is actually
  rendered — `--danger` ≥ 4.5:1 as error text; `--success` / `--warning` /
  `--info` ≥ 3:1 as a border/tint; the derived `-strong` text variants ≥ 4.5 (≥ 7
  under `prefers-contrast: more`) — and a seed that can't meet its bar fails the
  build with a per-token diagnostic instead of shipping an unreadable theme.
  `--info` defaults to the accent when unset. Composes with `--primary` and
  `--neutrals`.
- **`--neutrals` palette generation.** `swiflow theme --primary X --neutrals`
  derives an accent-tinted neutral ramp (`--sw-bg` / `--sw-surface` / `--sw-text`
  / `--sw-border`) with contrast-proven text-on-surface, plus a
  `prefers-contrast: more` block.
- **`--sw-warning` / `--sw-info` semantic tokens.** Two new tokens in the
  SwiflowUI base sheet: `--sw-warning` (amber — full light/dark, `-strong`,
  `prefers-contrast`, and P3 treatment) and `--sw-info` (aliases `--sw-accent`,
  independently overridable). Wired into `Badge` (`.warning` / `.info` variants)
  and `Toast` (`.warning` variant + the previously-missing info border), so the
  status set is now complete (danger / success / warning / info).
- **`@property`-registered design tokens.** The `--sw-*` contract registers its
  scalar tokens (`<length>` / `<time>` / `<number>`) and color tokens (`<color>`)
  via `@property`, so they are type-validated (a malformed app override is ignored
  rather than poisoning the cascade) and animatable (e.g. `--sw-border-width` can
  transition as it thickens under `prefers-contrast`).

### Changed

- **Generated accent and status colors ship a progressive `oklch()` line** after
  their sRGB hex fallback, rendering at the display-P3 gamut edge on capable
  displays — richer color with lightness and hue preserved (so contrast is
  unchanged) and the identical sRGB hex everywhere else. Neutrals stay hex-only.
- **SwiflowUI base tokens now live in `@layer swiflow.base`,** so an app's own
  unlayered `:root` overrides — and a generated `theme.css` — reliably win
  regardless of stylesheet injection order.

**Stability: stable for pre-1.0 usage.**

---

## [0.3.3] — 2026-06-23

### Changed

- **Production builds now ship minified runtime JS.** `swiflow build` emits
  esbuild-minified `swiflow-driver.js` / `swiflow-service-worker.js` (and the
  region runtime when used); `swiflow dev` keeps the readable variant for
  debugging. The CLI binary stays Node-free — minification runs at build time
  via the embed codegen.
- **Region JS is scaffolded only when used.** Plain projects (including the
  HelloWorld starter) no longer carry `swiflow-regions.js` /
  `swiflow-region-guest.js` (~15KB of previously-dead files). `swiflow init`,
  `dev`, and `build` emit the region pair only when `index.html` references it.
- **Renamed `swiflow-sw.js` → `swiflow-service-worker.js`** for clarity.

### Migration

- An already-deployed `swiflow-sw.js` service worker is not auto-unregistered
  by the renamed worker. Re-deploy and hard-reload; or unregister the old SW
  manually in DevTools → Application → Service Workers.

---

## [0.3.2] — 2026-06-23

### Fixed

- **`swiflow doctor` now catches a WASM SDK that doesn't match the compiler.**
  Previously it greenlit any installed wasm SDK, so a 6.3 SDK against a 6.3.2
  compiler passed `doctor` and then failed at `swiflow dev`/`build` with
  "module compiled with Swift 6.3 cannot be imported by the Swift 6.3.2
  compiler". Doctor now compares the SDK version against `swift --version` and
  fails with the exact `swift sdk remove` + `swift sdk install` remediation on a
  mismatch.

---

## [0.3.1] — 2026-06-23

Distribution: prebuilt CLI binaries. No library or API changes.

### Added

- **Prebuilt `swiflow` binaries.** Tagged releases now attach a ready-to-run
  CLI for **macOS arm64** and **Linux x86_64** (each a `.tar.gz` with a
  `.sha256` checksum), so installing no longer requires compiling from source.
- **`install.sh`.** A `curl … | sh` installer that detects your platform,
  verifies the checksum, and installs to `/usr/local/bin` (override with
  `SWIFLOW_INSTALL_DIR`; pin a version with `SWIFLOW_VERSION`).

### Notes

- The binary still shells out to your Swift 6.3 toolchain and the WebAssembly
  SDK to build apps — the one-time `swift sdk install` step is unchanged.
- Building from source (`swift build -c release --product swiflow`) remains
  supported, and is the path for hosts without a prebuilt binary (Intel Mac,
  Linux arm64).

---

## [0.3.0] — 2026-06-22

Type-reducer macros for the Query/Mutation data layer: declare a query or
mutation as a plain `struct` and let the macro synthesize the conformance and
the boilerplate.

### Added

- **`@Query` / `@Mutation`.** Attach to a `struct` to synthesize `Query` /
  `Mutation` conformance plus the memberwise initializer — you write only the
  identity, the captured dependencies, and `fetch` / `perform`. A hand-written
  `queryKey` or `init` is never overridden; `@Query(prefix:)` sets a custom
  cache-key prefix. As with Apple's `@Observable`/`Observable`, the macro and
  the protocol share a name in one module, so the idiomatic form is a bare
  `@Query struct …` — no explicit `: Query` needed.
- **`@Key` + `QueryKeyConvertible`.** `@Key` marks a query's identity
  properties; `queryKey` is derived from them in source order. Identity types
  conform to `QueryKeyConvertible` (`Int`, `String`, `Bool`, and
  `RawRepresentable` enums out of the box).
- **`@MutationState` auto-init.** `@Component` now synthesizes `init()` for
  zero-arg `@MutationState` properties, so a component of mutations no longer
  needs a hand-written initializer that only restates their names. Capturing
  mutations (those with stored dependencies) still take an explicit init.

**Stability: experimental — interface may change.**

## [0.2.1] — 2026-06-17

Developer-experience polish for SwiflowUI.

### Added

- **`size:` on `Toggle` and `Checkbox`.** Both now take
  `size: ControlSize` (`.sm`/`.md`/`.lg`, default `.md`), matching the rest of
  the form-control family. The box/track/thumb and label scale together via the
  token-driven `.sw-check--*` / `.sw-switch--*` font-size.
- **Opt-in `key:` on the overlay facades.** `Alert`, `Prompt`, `Autocomplete`,
  and `Dropdown` reuse their backing component across renders, which freezes the
  props captured at first mount. A new `key: String? = nil` parameter forces a
  rebuild with fresh props whenever the key changes — the escape hatch the docs
  described but never actually exposed. Default `nil` preserves the existing
  reuse behavior.

### Changed

- **`import SwiflowUI` re-exports `Swiflow`.** Using SwiflowUI no longer needs a
  separate `import Swiflow` for `VNode` / `@State` / `Binding` / `Attribute`
  (you still `import SwiflowDOM` for the renderer entry point). Mirrors how
  `SwiflowDOM` already re-exports the core.
- **Form controls catch a smuggled value binding (debug builds).** Passing
  `.value` / `.checked` / `.on(.input)` / `.on(.change)` through a control's
  trailing attributes silently overwrote the control's own binding; it is now a
  `swiflowDiagnostic` precondition in debug builds (compiled out of release), so
  the mistake is loud instead of a dead control. Drive the value through the
  `text:` / `isOn:` / `field:` parameter.
- **`.modifierClass` is now internal.** The CSS-class helper on the control
  variant/size enums (`ButtonVariant`, `BadgeVariant`, `ControlSize`, …) was
  unintentionally `public`; it is an implementation detail of the `.sw-*`
  stylesheet, not API.

**Stability: stable for pre-1.0 usage.**

## [0.2.0] — 2026-06-14

### Added

- **SwiflowUI — accessible, token-driven component library.** A component set
  for building real UIs without dropping to raw HTML: layout
  (`VStack`/`HStack`/`Grid`/`Spacer`/`Divider`), controls (`Button`,
  `TextField`, `Toggle`, `Checkbox`, `Select`, `RadioGroup`), feedback
  (`Spinner`, `ProgressView`, `Card`, `Badge`), and native overlays (`Alert`,
  `Prompt`, `Toast`). Built on semantic HTML (`<button>`, `<input>`,
  `<dialog>`, the Popover API), so roles/keyboard/focus come from the platform;
  ARIA is added only where a component departs from native. Every value reads a
  `--sw-*` token, so apps re-skin via token overrides and adapt to dark mode,
  `prefers-contrast`, `prefers-reduced-motion`, `prefers-reduced-transparency`,
  and wide-gamut displays with no component code — verified in the emitted CSS
  (`ThemeTests`) and at runtime (`Tests/playwright/theming.spec.ts`). The
  HelloWorld scaffold is built from it (retiring its hand-rolled toast +
  sign-in form). Add `.product(name: "SwiflowUI", package: "Swiflow")`; see
  [`docs/guides/swiflowui.md`](docs/guides/swiflowui.md) and
  [`docs/guides/swiflowui-theming.md`](docs/guides/swiflowui-theming.md).
  **Stability: stable for pre-1.0 usage.**
- **`#css` macro — real CSS in Swift.** Write actual CSS in a string literal
  (`#css(""" .row { display: grid; } """)`); the macro validates structure at
  compile time (unbalanced braces, malformed declarations, `@import` are
  compile errors) and passes everything else to the browser verbatim — new
  CSS features work without a Swiflow release. Scoping rides native CSS
  nesting: `:host` styles the component root, other selectors match
  descendants, and non-nestable at-rules (`@keyframes`, `@font-face`,
  `@property`) are hoisted automatically. Composes with the builder DSL via
  `+`; the DSL remains fully supported. See `docs/guides/styling.md`.
  **Stability: stable for pre-1.0 usage.**

## [0.1.9] — 2026-06-11

### Added

- **Automated releases.** Pushing a `vX.Y.Z` tag now publishes the matching
  GitHub Release automatically, with notes lifted from this file's
  `## [X.Y.Z]` section (`.github/workflows/release.yml`). A git tag alone
  never created a Release, so the "Latest release" badge used to lag behind
  the newest tag.

## [0.1.8] — 2026-06-11

### Changed

- **Event/binding modifiers moved into the `Swiflow` core module.**
  `.on`, `.value`, `.checked`, `.selection`, and `.ref` now register through a
  core ambient handler seam instead of living in `SwiflowDOM` — no user-facing
  API change (SwiflowDOM re-exports Swiflow), but the modifiers now work
  headlessly under `SwiflowTesting`.
- **`SwiflowTesting` is now faithful to the browser renderer.** Components
  under test render through the production diff path: `onAppear`/`onChange`/
  `onDisappear` fire, state changes re-render from the root, and synthetic
  events carry `targetValue`/`targetChecked` the way the JS driver sends them.
- **Renamed two library modules** for clearer intent (no API surface change —
  only the module names). Dependent projects must update `import` lines and
  `.product(name:)` references:
  - `SwiflowHTTP` → **`SwiflowFetcher`** — the JSON-over-`fetch` client.
  - `SwiflowWeb` → **`SwiflowDOM`** — the WASM/DOM renderer.

  `swiflow init` templates and all bundled examples now use the new names.

### Fixed

- **Service worker updates.** `swiflow build` now stamps a per-build tag into
  `swiflow-sw.js`, so browsers detect new deploys and refresh the offline
  cache (previously returning visitors were pinned to the first deploy).
- **Dev loop:** editing HTML/JS now reloads the page (previously only a wasm
  hot-swap was broadcast and HTML edits never appeared); rapid saves no
  longer race the hot-swap; editing `scopedStyles` no longer shows stale CSS
  after a hot-swap.
- **Driver resilience:** a single failing patch no longer aborts the rest of
  the frame, and driver/boot errors are `console.error`'d in production
  builds (previously dev-only).
- **`swiflow doctor`** now probes the macOS swift.org toolchain and
  binaryen's `wasm-opt` — the two missing pieces that made builds fail on
  machines where doctor passed.
- **XSS allowlist:** the postfix `.attr("href", …)` modifier now routes
  through `URLSanitizer` like the prefix path (the documented invariant had
  a public bypass).
- **Query cache growth:** entries are garbage-collected `gcTime` (default
  5 minutes, configurable per query) after their last subscriber unmounts.
- **Router:** history mode no longer drops `?query` strings on back/refresh;
  `Link` hrefs are mode-aware (`#/path` under the default hash mode, so
  cmd/click and copy-link resolve to the route).
- **SwiflowUI:** `installBaseStyles()` before `Swiflow.render` now works —
  the style registry buffers until the DOM sink is installed.
- **`@State var x: Optional<Int>`** (long spelling) now gets the same
  HMR nil-handling as `Int?`.
- **Multi-root HMR:** a hot-swap now preserves `@State` across all mounted
  roots, not just the last-mounted one.
- **Release bundle:** the dev inspection API (`window.__swiflow`) and HMR
  snapshot/restore machinery are compile-time stripped from `swiflow build`
  output — smaller wasm, and no dev-only state-export surface in production.
- **Optimistic mutations:** a failed mutation no longer rolls its cache key
  back over a *concurrent* mutation's newer value (or cancels that mutation's
  refetch) — rollback now skips keys that were superseded after the optimistic
  write.
- **`SwiflowFetcher`:** non-finite numbers (`NaN`, `±Infinity`) serialize as
  JSON `null` (matching `JSON.stringify`) instead of the invalid tokens
  `nan`/`inf`.
- **Router:** captured path params are now percent-decoded like query params —
  `/users/john%20doe` yields `params["id"] == "john doe"`.

### Removed

- Internal Phase-2a `viewProducer` Renderer mode (never part of the public
  API; no behavior change for apps).

### Added

- `TestHarness.check(_:at:checked:)` — simulate checkbox/radio toggles.
- `TestHarness.unmount()` — tear down the tree, firing `onDisappear`.

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
