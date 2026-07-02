# Pre-launch audit — full framework (2026-07-01)

**Scope:** all 11 modules, 25.4k source LOC, audited in 9 units across three dimensions — **SOUND** (correctness), **SWIFT** (best practices / the about-to-freeze public API), **SLOP** (AI-generation artifacts). Eight units were audited by dedicated read-only agents and one (Router/Color/Testing) directly; **every P0/P1 was independently re-verified against the code before entering this report** — including four claims that were downgraded and two that were cleared entirely (see the Adjudication log at the end). Compile-breaking claims were reproduced with real host builds.

## Verdict

**The framework is architecturally sound and is not AI slop.** Zero `fatalError`/`try!` in source, one TODO in the whole tree, ~1:1 test-to-source ratio, Swift 6 strict concurrency throughout, and every module showed genuine engineering discipline (see Strengths). **No day-one crash-on-idiomatic-use bug was found.** What the audit did find is a launch-shaped work list: **2 confirmed P0s** (both loud compile-time failures, not silent), **6 P1-HIGH** items that undermine advertised guarantees or robustness, ~15 further P1s dominated by public-API-freeze decisions, and a tail of P2 polish.

## Fix waves (recommended order)

### Wave 1 — before announcing (correctness / guarantee-breaking)

| # | Finding | Where | Why first |
|---|---------|-------|-----------|
| 1 | **[P0] Multi-binding state macros fail on idiomatic Swift** — `@State var width, height: Double = 0` → opaque "can only apply to a single variable" + "invalid redeclaration of `$a`" (same for `@MutationState`/`@ReducerState`). Reproduced by host compile. | `StateMacro.swift:73`, `MutationStateMacro.swift:15`, `ReducerStateMacro.swift:15` | The single most likely first-five-minutes bounce for a new user. Fix: diagnose cleanly like `@Key` does (`QueryMacro.swift:89`), or iterate bindings. |
| 2 | **[P0] DataTable row-click fires on checkbox/action clicks** — `.on(.click)` on `<tr>` has no `isSelfTarget` guard; selecting a row also "opens" it, clicking Edit also navigates. | `DataTable.swift:527` | Flagship component, mainstream combo (`onRowClick` + `selection`/actions). Fix: the exact `isSelfTarget` pattern Alert/Prompt already use. |
| 3 | **[P1-HIGH] Scoped-CSS comma-selector leak** — `rule(".a, .b")` emits everything after the first comma **unscoped**, twice — silently defeating per-component isolation. Ships today (`CityCard+Styles.swift:20`). `#css` macro path unaffected. | `CSSSheet.swift:41-50` | Silently breaks a selling point. Fix: split on top-level commas, scope each part. |
| 4 | **[P1-HIGH] App-killing `Int(Double)` trap on `window.__swiflowDispatch`** — wasm32 `Int` is 32-bit, so any JS number beyond ±2³¹ (a timestamp) traps and kills the app; the global is reachable by any page script. Guarded pattern exists in-module (`HMRBridge.swift:227`). | `DispatcherBridge.swift:28` | One-line `Int(exactly:)` hardening on the function routing every DOM event. |
| 5 | **[P1-HIGH] Query entry recycling: zombie fetch overwrites fresh data** — `startFetch`'s task never checks `Task.isCancelled` after its await; new entries start at generation 0, so an evicted-then-recycled key accepts a stale zombie commit as fresh. Enabled by the fetch layer having no AbortController/timeout. | `QueryClient.swift:80-102`, `HTTPClient.swift:94-120` | Silent stale-data-as-fresh. Fix: `guard !Task.isCancelled` before commit + entry-identity compare; wire AbortController + timeout. Add eviction+recycle to the fuzz model. |
| 6 | **[P1-HIGH] Poll retry storm** — after retries exhaust, `lastFetched` stays frozen-stale and the poll branch refires **every tick** instead of every interval, defeating `maxRetries` and hammering a down server; same root cause makes focus-refetch ignore retry state. | `QueryClient.swift:111-121, 168-176` | Common failure mode (polling + server down) becomes a per-client thundering herd. Fix: gate poll/focus on retry state. |

### Wave 2 — API-freeze decisions (before the surface is public)

- **72 single-word public free functions in `CSSProperties.swift`** (`color`, `width`, `position`, `background`, `border`…) — near-guaranteed collisions with app code; `transition` already exists in 3 shapes. Decide: namespace under `CSS.` or accept + document. *(This is the biggest deliberate API decision on the list.)*
- **State-peer projections don't propagate host access level** — a `public` component with `@State public var count` gets an *internal* `$count` (`StateMacro.swift:107` + siblings; `SynthesizedAccess` exists for exactly this and isn't used here). Live trap for the first public bindable component.
- **`@Query`/`@Mutation` double-`@MainActor`** — a user writing the redundant-but-natural `@MainActor func fetch()` gets "multiple global actor attributes" (reproduced by host compile). Port `ComponentIsolation.memberHasIsolation`'s guard into `MainActorWitnessIsolation.swift:31`.
- **Needlessly public / mis-scoped**: `RAFScheduler` (public, zero external consumers → internal), `Renderer.teardown()` (package → internal).
- **RadioGroup is missing the `size:` param** every sibling form control has (`RadioGroup.swift:23`) — the one asymmetry in an otherwise uniform control API.
- **`nonisolated(unsafe)` sweep** — ~10 globals in SwiflowDOM + `AmbientEnvironment.current` (`Environment.swift:83`) are only ever touched from `@MainActor` code but opt out of checking entirely, uncommented — against the codebase's own justify-every-unsafe bar. Convert to `@MainActor` namespaces (compiler-verified) in one pass. Same for the unjustified `@unchecked Sendable` on `FormController`.
- **Mutation API gaps**: success never writes `perform`'s output back — optimistic edit + empty `invalidations` leaves the cache stuck on the guess with no diagnostic; `reset()` doesn't detach an in-flight mutation (stale completion resurrects state). Both fixable with the existing generation/epoch pattern + a DEBUG diagnostic.
- **`swiflow init` name validation** — unvalidated `name` scaffolds outside `--path` (`init "../../evil"`); reject `/` and outside-parent resolution. *(Corrected from the agent's report: the failure-path delete only ever removes the directory it just created — no arbitrary-delete.)*
- **Dev-server port-in-use UX** — `EADDRINUSE` surfaces as a raw NIO error on the most common first-run failure; catch → "port 3000 in use — pass `--port`".

### Wave 3 — polish (P2, batched by kind)

- **Dead code:** `HMRWalker.applyRestore` + `wireState` have zero production callers — the 5-file HMR restore test suite exercises a duplicated path production doesn't run (false coverage for a flagship dev feature); the `@MacroState` migration branch in `ComponentMacro.swift:80-98` is vestigial.
- **Wrong load-bearing comments:** six SwiflowDOM files describe a JSClosure-retention mechanism JavaScriptKit doesn't use (it self-registers in `sharedClosures`; teardown is JS-side FinalizationRegistry) — no live bug, but the safety narrative a future contributor will reason from is wrong.
- **Copy-paste extraction:** exit-anim/remove block ×3 in the diff (these are also the fragment-body bug sites — one extraction fixes both); `encodeStateMap` duplicated between DevAPI and HMRBridge; toolchain resolution duplicated between Build/Dev commands (already drifted once); `value`/`checked`/`selection` duplicated across the Attribute and VNode surfaces; `performance.now()` ×4.
- **Fragment-body diff family** (downgraded P0→P1 for low reachability, listed here because the *fix* is Wave-3-shaped): a component whose `body` is a bare `.fragment` yields a phantom DOM handle (patch-batch abort on identity swap; silent exit-animation no-op). The only diff footgun with **no** DEBUG guard while every sibling hazard traps. Fix: add the guard diagnostic + route through `collectDOMRoots`; consider a typed `DOMHandle` vs structural handle.
- **Lifecycle-cleanup consistency:** RouterRoot never removes its window listener; Link never clears its click closure; `TimerHandle` lacks `deinit { cancel() }`.
- **Small correctness/UX:** memoKey silently freezes `.ref`/`.task` (document or reconcile-on-hit); region decode failures silently swallowed (asymmetric with the encode-side diagnostic); `Field.init` has an undocumented side effect + FormController must be *replaced* per record (document); `try?` around compile-cache creation prints false success; virtualized DataTable should add explicit `role=table/rowgroup/row` (display-override ARIA trap — verify in a real SR); RadioGroup `name` collision needs a DEBUG diagnostic; bare query flags dropped; non-2xx body discarded in HTTPError; PersistentStore needs a single-flight open guard; `EnvironmentValues.==` reflexivity caveat (document); StateMacro's wrong diagnostic for computed properties; Prompt doc-comment split; dev-server symlink prefix-check (defense-in-depth; loopback + no CORS verified).

## Strengths (what's genuinely good — keep it)

- **The diff engine**: a correct Vue3/Inferno LIS keyed reconciler; the DOMAnchors trio elegantly unifies 0..N-rooted fragments; strong DEBUG-diagnostic discipline (dup keys, mixed keying, anchor cycles, reused instances) — the fragment-body gap is notable precisely because it's the *only* unguarded hazard.
- **Isolation discipline**: `MainActor.assumeIsolated` at every JS→Swift boundary without exception; no `@unchecked Sendable` band-aids in the data layer; the macro isolation work (auto-`@MainActor`) is host-compile-gated.
- **A11y is designed, not bolted on**: roving-tabindex menu, APG combobox with reasoned mousedown-vs-click ordering, `isSelfTarget` backdrop dismissal, WCAG 2.2.1 toast pause.
- **Security-relevant code is careful**: `URLSanitizer` closes the `java\tscript:` bypass; `percentDecode` does strict UTF-8 validation with documented trade-offs; the CLI has zero shell-injection surface (argv-arrays everywhere) and a loopback-only, GET-only dev server.
- **Typed, actionable errors** throughout (PaletteFailure, HTTPError, the CLI's remediation hints); generated files are cleanly marked and regenerated in lockstep.
- **Comment density (~34% in core) is largely earned** — most long comments document *why* (invariants, browser quirks, rejected alternatives), which is the opposite of slop. The exceptions are catalogued above (restating-the-code cases, one speculative 30-line caveat, and the six wrong JSClosure comments).

## Cross-cutting themes

1. **Sibling-inconsistency is the dominant defect shape** — nearly every real finding is "X does it right, its sibling doesn't": ComponentIsolation guards double-isolation but MainActorWitnessIsolation doesn't; @Key diagnoses multi-binding but the state macros don't; HMRBridge range-checks its narrow but DispatcherBridge doesn't; BackgroundRevalidation removes its listener but RouterRoot doesn't; the encode side diagnoses but the decode side swallows. **Fix recipe: when touching any of these, port the sibling's guard.**
2. **Golden macro tests are structurally blind** — `assertMacroExpansion` type-checks nothing and doesn't expand peer macros; both macro P0-class findings (and this session's earlier `@MainActor` peer bug) were invisible to green golden suites and only surfaced under real host compiles. The `BareComponentIsolationTests` pattern (compile-is-the-test) should be extended to the multi-binding and access-level cases when fixed.
3. **The fuzz suite's model has two gaps** — entry eviction+recycling and polling-under-persistent-failure. Both confirmed bugs live exactly there. Extend the model when fixing Wave-1 items 5–6.
4. **Escape-hatch hygiene**: the codebase's own bar (justify every `nonisolated(unsafe)`/`@unchecked Sendable`) is met ~80% of the time; the sweep in Wave 2 closes the rest and converts most to compiler-checked `@MainActor` storage.

## Adjudication log (claims corrected during verification)

Agent findings that did **not** survive verification, kept for honesty and to spare future re-litigation:

- Toast coalesce-timer "bug" → the **deliberate, user-approved v1 design** (recurrence intentionally doesn't reset the timer).
- `Link`'s one-time `navigate` capture → **safe** (RouterRoot's closures weak-delegate to the live instance).
- `EnvironmentValues` non-reflexive `==` → downgraded (an Equatable-constrained overload exists; only non-Equatable values hit the documented conservative path).
- Unkeyed-sibling remount churn → downgraded (a DEBUG `preconditionFailure` trap catches mixed keying immediately in dev).
- Fragment-body phantom handle → P0→P1 (requires a deliberate `.fragment` body no example/builder produces — but left unguarded, hence Wave 3).
- `swiflow init` "deletes an arbitrary directory" → **corrected**: the failure-path delete only removes the directory the command itself created; the write-traversal stands.
- Dev-server symlink read-through → downgraded (loopback-only + **no CORS headers**, verified — not browser-exfiltrable cross-origin).

*Method note: findings were produced by 8 scoped read-only audit agents + 1 direct pass, then every P0/P1 was re-verified by the controller against the code (including two host-compile reproductions and one empirical plugin-binary check). Severity labels in this report are the adjudicated ones.*
