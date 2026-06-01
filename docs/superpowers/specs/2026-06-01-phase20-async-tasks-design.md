# Phase 20 — Async Task Effects (`.task` / `.task(rerunOn:)`)

**Status:** Draft — revised after Taylor-Otwell API review (awaiting approval)
**Date:** 2026-06-01
**Predecessor:** Phase 19b (`docs/superpowers/specs/2026-05-28-phase19b-render-version-push-tick-design.md`).
**Successor (separate brainstorm):** a data-fetching / caching library (à la TanStack Query / SWR). This phase is the **foundation** that library will ride on; the library itself is explicitly out of scope here.

## Context

Swiflow has no first-class way to run async work tied to a component's lifetime. The only async primitive in the codebase today (`Task { }`) appears solely in server-side CLI code; nothing browser-facing awaits. The inferred "kick off a `Task` in `onAppear`" pattern has never actually been exercised in the browser — and as Phase 20's verification confirmed, it would **silently never resume there** because the SwiftWasm `JavaScriptEventLoop` global executor is not installed.

The motivating north star is a data-fetching library. A query layer's entire quality ceiling is set by the async primitive beneath it: cancellation, dependency-keyed refetch, and request dedup all depend on lifecycle-bound async effects existing in the core. So we build the foundation first, get it clean and well-tested, then design the query library on top in a separate cycle.

We deliberately reject the more ambitious "async `body`" / Suspense model (see Rejected Alternatives). Swiflow's `body` stays synchronous; async work is declared as a lifecycle-bound *effect*, mirroring SwiftUI's `.task`.

## Goal

A declarative, lifecycle-bound async effect for components:

```swift
var body: VNode {
  div {
    switch user {
      case .success(let u): text(u.name)
      case .loading:        text("…")
      default:              empty()
    }
  }
  .task(rerunOn: userID) {
    do {
      user = .success(try await fetchUser(userID))
    } catch {
      user = .failure(error)
    }
  }
}
```

- **Started** when the decorated node mounts.
- **Re-run** (cancel + restart) when `rerunOn` changes between renders.
- **Cancelled** when the node (or its owning component's subtree) unmounts.
- Plus a no-dependency form, `.task { }`, that runs once on mount and cancels on unmount.

Note the call site carries **only** the consumer's domain `do/catch` — no `guard !Task.isCancelled` and no `catch is CancellationError`. The runtime **drops writes from superseded and dead tasks** (see Semantics → Cancellation), so stale data can neither re-render nor clobber stored state. That correctness lives in the bedrock, not at every call site.

Plus the `AsyncTestHarness` needed to test all of the above deterministically, and the `JavaScriptEventLoop` wiring needed to make it work in the browser at all.

## Scope

**In:**
- `.task { }` and `.task(rerunOn:)` modifiers on `VNode`, collected during diff like `.on(.click)` handlers.
- Diff-integrated task lifecycle: start on mount, cancel+restart on `rerunOn` change, cancel on unmount — riding the existing node lifecycle, no parallel machinery.
- A task registry/runner that tracks spawned `Task` handles + a per-slot **live generation** (for cancellation in production, for `await` in tests, and for the superseded-write guard).
- A **superseded-/dead-task write guard**: a `@State` write originating from a task that has been superseded (its slot moved to a newer generation) or whose component has unmounted is **dropped at the write** — neither the stored value changes nor `markDirty` fires. This makes the primitive correct-by-default and removes the cancellation ceremony from every call site.
- `JavaScriptEventLoop.installGlobalExecutor()` wired into the web bootstrap (`Swiflow.render(into:)`), and the `JavaScriptEventLoop` product added to the `SwiflowWeb` target.
- `AsyncTestHarness` + `settle()` in `SwiflowTesting`, with a controllable IO stub pattern and a settle iteration cap.
- A `TaskBody` typealias for the closure signature, and a DEBUG `swiflowDiagnostic` for stable-slot violations.
- A worked fetch example.
- Documentation covering the sharp edges (purity story, restart semantics, the write-guard guarantee).
- Unit/integration tests for lifecycle, rerun, cancellation, and the superseded-/dead-task write guard.

**Explicitly out (separate brainstorm or not pursued):**
- The data-fetching / caching library itself: `QueryClient`, `QueryState<T>`, caching, dedup, invalidation, mutations, persistence.
- Any HTTP/`fetch` wrapper. (`fetchUser` in examples is hand-rolled JavaScriptKit.)
- Async `body` / Suspense / concurrent rendering (rejected — see below).
- `throws` task closures with a framework error sink (rejected — see below).
- An `@Effect` property wrapper or a `tasks()` lifecycle method (rejected — see below).
- Variadic-generic (parameter pack) multi-dependency `rerunOn:` — a fast-follow once the core guard is proven; v1 ships the single-`Dependency` signature (compose via struct/array). See Dependencies.

## API surface

A new modifier on the `VNode` DSL, alongside `.on(...)`:

```swift
/// The body of a `.task` effect. Non-throwing; runs on the main actor.
public typealias TaskBody = @MainActor @Sendable () async -> Void

public extension VNode {
    /// Run once when this node mounts; cancel when it unmounts. Never restarts.
    func task(_ body: @escaping TaskBody) -> VNode

    /// Run when this node mounts; cancel and re-run whenever `rerunOn` changes
    /// between renders; cancel when it unmounts.
    func task<Dependency: Equatable>(rerunOn dependency: Dependency, _ body: @escaping TaskBody) -> VNode
}
```

- The closure is **non-throwing** (`TaskBody`). Errors are handled inside the closure by the consumer (see Semantics → Errors). The `TaskBody` typealias keeps the four-attribute signature from leaking into every doc comment and call site.
- `rerunOn` takes any `Equatable` `Dependency` (the generic is named for what it *is*, not "id" — that label was a SwiftUI vestige). Restart is decided by `!=` against the prior render's value — the same Equatable-keyed, fire-on-change contract as the existing `onChange(of:perform:)` (`Sources/Swiflow/Reactivity/OnChangeStorage.swift`). The two are documented as one family. See **Dependencies** below.
- Multiple `.task`s may decorate one node; they are identified by declaration order on that node (the "stable slot" rule below).

## Dependencies (`rerunOn:`)

`rerunOn:` is an **explicit re-run trigger**, not a dependency audit. This is a deliberate departure from React's `useEffect` deps array, and the distinction is the whole point:

| Aspect | React `useEffect(fn, [a, b])` | `.task(rerunOn:)` |
|---|---|---|
| What you pass | An untyped array | One `Equatable` value (compose for many) |
| Comparison | `Object.is`, element-by-element, untyped | `!=`, type-checked, synthesized |
| Contract | **Exhaustive** — must list everything the closure reads, enforced by a lint | **Explicit trigger** — list only what should *cause* a re-run |

We do **not** import the "declare every value you read" obligation (the footgun behind rejecting `@Effect`). The closure reads current `self` values freely; only `rerunOn:` decides re-runs. The honest consequence, which the docs must state: if the closure's *result* depends on a value you did not put in `rerunOn:`, it will not re-run when that value changes — your explicit choice, not a silently-wrong lint situation.

**One dependency** — any `Equatable`: `rerunOn: userID` (`Int`), `rerunOn: query` (`String`), `rerunOn: filter` (`enum`).

**Several dependencies** — compose into one `Equatable` value:
- A **struct key** is the recommended idiom: `rerunOn: SearchKey(text: q, page: n)` with synthesized `Equatable`. Heterogeneous, type-safe, self-documenting — and it foreshadows the future query library, where the dependency *is* a query key.
- An **array** works for the homogeneous case: `rerunOn: [userID, page]`.
- A raw **tuple `(a, b)` does *not* work**: tuples cannot *conform* to `Equatable` (even though `==` exists for them up to arity 6). Use a struct.

**Parameter packs (fast-follow, not v1)** — Swift 6 variadic generics could allow a type-safe *heterogeneous* list directly: `func task<each Dependency: Equatable>(rerunOn deps: repeat each Dependency, …)` → `.task(rerunOn: userID, filter, page) { … }`. This is a genuine win over TS (which cannot express a type-safe heterogeneous deps list), but it adds pack-comparison machinery. Deferred to a fast-follow so Phase 20 stays focused on de-risking the write guard and the JS executor; v1 ships the single-`Dependency` signature, which struct/array already cover.

## Semantics

### Lifecycle & identity
Tasks ride the diff's existing node create / update / remove signals — the same path `.on(.click)` handlers already use.

- **Node created (mount)** → start each task on the node.
- **Node persists (re-render, same position/type/key):**
  - `.task { }` → leave running, never restart.
  - `.task(rerunOn: v)` → compare `v` to the prior render's value. Equal → leave running. Changed → cancel the running task, start fresh.
- **Node removed (unmount), including via owning component unmount** → cancel each task on the node.

**Identity** = the mounted node the modifier decorates × the task's declaration slot on that node. **Stable-slot rule:** do not conditionally vary the *number* of `.task`s on a single node — slot indices must be stable across renders. This is the same constraint handlers/attributes already carry. Rather than ship it as a docs-only footgun, a **DEBUG `swiflowDiagnostic`** fires when a node's `.task` count changes between renders (the same facility that already guards duplicate keys and mixed keyed/unkeyed children in `Diff.swift`) — the "rules-of-hooks" trap is caught loudly in development and compiled out of release.

Anchoring to the node (not the component) is a deliberate choice: it is a direct reuse of the diff, and a component unmount cancels every task in its subtree for free because the diff already removes those nodes.

### Cancellation & the superseded-write guard
Cancellation is cooperative (`Task.cancel()`); rerun is **latest-wins** (cancel in-flight, start new). The sharp edge is a cancelled task that resumes *after* its replacement and (a) triggers a stale re-render and (b) clobbers the stored `@State` value. Rather than push a correctness guard onto every call site, the **runtime drops the stale write itself** — the primitive is correct-by-default.

**Mechanism.** Each `.task` slot holds a monotonically increasing **live generation**; a rerun bumps it. When the runtime spawns a task it stamps the work with a `@TaskLocal` token carrying `(slotID, generation)`:

```swift
TaskRunner.$current.withValue(token) { await body() }
```

A `@State` write consults that task-local at the point of mutation. If a token is present **and** it is stale (its generation ≠ the slot's live generation, or the slot/component has unmounted), the write is **dropped**: the stored value is left unchanged and `markDirty` does not fire. Writes with no token (event handlers, etc.) and writes from the live task proceed normally.

**Why this is cheap on the macro.** `@State` already expands to a `didSet` that calls `scheduler.markDirty(owner)`. The guard is **one additive line at the top of that `didSet`**: if the current task token is stale, restore `oldValue` and return before `markDirty`. Swift does **not** re-fire `didSet` for an assignment made inside the same observer, so the restore is safe and non-reentrant. The macro change is a single emitted guard calling one runtime function — it does not restructure `@State`, which keeps it well clear of the isolation pitfalls that have bitten the macros before (still verified early — see Risks).

This subsumes the old "dead-component write guard": a dead component is just a slot with no live generation, handled by the same check.

### Errors
The closure is non-throwing. The framework has no notion of what an error *means* (no `QueryState`, no `.failure`), so catching it could only log-and-swallow — the silent-failure anti-pattern. Forcing the `catch` at the call site puts error handling where the state lives, and matches SwiftUI's `.task`. This is the consumer's *domain* `do/catch` — distinct from the *lifecycle* race ceremony, which the write guard above absorbs. So the raw call site carries exactly one burden (map success/failure to your state) and not two; the query layer later removes even that.

Note: because superseded/cancelled tasks have their writes dropped, the consumer does **not** need to special-case `CancellationError`. A `CancellationError` surfacing in the `do/catch` would set `.failure`, but that write is itself dropped by the guard (the task is, by definition, stale), so it never reaches state.

## Prerequisite: `JavaScriptEventLoop` (load-bearing)

Verified during this phase:
- `JavaScriptEventLoop` is **not** a declared dependency — `Package.swift` pulls only `JavaScriptKit` from the swiftwasm package.
- `installGlobalExecutor()` is **never called** anywhere in `Sources/` or `examples/`.

Without the global executor, `Task { }` / `await` resume in **tests** (host Swift has a default executor) but **silently hang in the browser**. Phase 20 must:

1. Add the `JavaScriptEventLoop` product to the `SwiflowWeb` target in `Package.swift`.
2. Call `JavaScriptEventLoop.installGlobalExecutor()` once, idempotently, at the top of `Swiflow.render(into:)` in `Sources/SwiflowWeb/SwiflowWeb.swift` (the single bootstrap chokepoint, called from each app's `@main`).

## `AsyncTestHarness` (deterministic async testing)

Lives in `SwiflowTesting`. Determinism is tractable because host/WASM execution here is effectively single-threaded and `@MainActor` — only ordering matters, not parallelism.

A **task registry** records every `Task` handle the runtime spawns for a `.task` effect (production reuses it for cancellation; tests reuse it for `await`). The harness exposes one core primitive:

```swift
let h = AsyncTestHarness(into: ...) { Profile(userID: 1, fetch: stub) }
h.mount()
await h.settle()                 // drive to quiescence
#expect(h.text == "Ada")
```

`settle()` loops to a fixed point:
1. `await` all currently-tracked in-flight task handles.
2. Flush the scheduler synchronously (apply state writes those tasks produced).
3. If the flush changed a `rerunOn` → new tasks spawned → repeat.
4. Terminate when no task is in-flight **and** no component is dirty.

Supporting pieces:
- **Controllable IO stub:** tests inject the async function (e.g. `fetch`) the component calls, so they can assert the `.loading` state, resolve a continuation, `settle()`, then assert `.success` — intermediate states are deterministic.
- **Settle iteration cap:** `settle()` bounds its loop rounds and throws a clear error if exceeded, so a runaway re-render/refetch cycle surfaces as a test failure rather than a hang.

## Architecture & files

No new target — this is core framework work.

| Concern | Module | File(s) |
|---|---|---|
| `.task` / `.task(rerunOn:)` modifier + `TaskBody` | `Swiflow` | `DSL/Modifiers.swift` (new `Attribute`-style case), `VNode.swift` |
| Task collection + lifecycle (start/rerun/cancel) | `Swiflow` | `Diff/Diff.swift` (ride node create/update/remove) |
| Task registry / runner + per-slot live generation + `@TaskLocal` token | `Swiflow` | new file, scheduler-adjacent (`Reactivity/`) |
| Superseded-/dead-task write guard | `Swiflow` | `SwiflowMacrosPlugin/StateMacro.swift` (one guard line in the emitted `didSet`) + a runtime check function; `Reactivity/Scheduler.swift` |
| Stable-slot DEBUG diagnostic | `Swiflow` | `Diff/Diff.swift` (`swiflowDiagnostic`) |
| JS executor install + dependency | `SwiflowWeb` | `SwiflowWeb.swift` (`render(into:)`), `Package.swift` |
| `AsyncTestHarness` + `settle()` | `SwiflowTesting` | new `AsyncTestHarness.swift`, reuse `TestRenderer` |
| Worked example | `examples/` | a fetch demo component |

`SwiflowWeb` changes are otherwise minimal: tasks mark state dirty, and `RAFScheduler` already batches dirty components per frame.

## Documentation requirements

A chunk of this primitive's cons are *legibility* cons, so docs are load-bearing (not an afterthought). The docs must explicitly cover:
- **The purity story:** the `.task` closure is *declared* in `body` but *runs later*, owned by the runtime on `@MainActor` — it is not executed during render. (`body` stays pure.)
- **Restart semantics:** `rerunOn` restarts (cancel + fresh start) on `!=`; bare `.task` never restarts; both cancel on unmount. Cross-reference `onChange(of:perform:)` so the Equatable-keyed family reads as one idea.
- **The write-guard guarantee:** writes from superseded/cancelled/dead tasks are dropped by the runtime, so the call site needs only its own success/failure `do/catch` — no `isCancelled` / `CancellationError` handling. (Documenting the guarantee replaces documenting a manual workaround.)
- **The stable-slot rule** for multiple tasks on one node — and that the DEBUG diagnostic will flag violations.

## Testing strategy

- **Lifecycle:** task starts exactly once on mount; cancels exactly once on unmount (mirrors the Trap 7 component-lifecycle test in `examples/EdgeCases`).
- **Rerun:** changing `rerunOn` cancels the prior task and starts a new one; unchanged value does not.
- **Superseded write dropped:** a slow prior run that resolves *after* a newer run has the write dropped at the `@State` mutation — the stored value is unchanged (not just the re-render suppressed) and no `markDirty` fires. Asserted on stored state, not only on rendered output, to catch the latent-staleness case.
- **Dead-task write dropped:** a task resolving after its component unmounts does not crash, does not mutate state, and does not mark dirty.
- **Stable-slot diagnostic:** varying the `.task` count on a node between renders fires `swiflowDiagnostic` in DEBUG.
- **`settle()` fixed point:** a task that triggers a `rerunOn` change is driven to quiescence; a runaway cycle hits the iteration cap and fails cleanly.
- **Browser smoke (Playwright):** the worked example actually resumes a `Task` and updates the DOM — the regression guard for the `JavaScriptEventLoop` wiring. (Per the Playwright-CI-gap note, run manually after this runtime change.)

## Risks & open questions

- **`@State` macro guard under WASM cross-compile (verify first):** the write guard adds one line to the `didSet` the `@State` macro emits. Confirm the emitted guard + the `@TaskLocal` read compile and run correctly under the WASM cross-compile *before* building on it — this is the macro-adjacent area that has bitten isolation before. The revert-in-`didSet` approach is chosen precisely to keep the change additive (no `@State` restructuring); if even that fights the cross-compile, fall back to gating only `markDirty` (drops the stale re-render) plus a documented value-staleness note, and escalate.
- **`@TaskLocal` propagation across the `await`:** confirm the token set via `TaskRunner.$current.withValue` is visible at the `@State` write that happens *after* an `await` suspension inside the task body (task-locals propagate to child scopes and across suspensions of the same task — verify in a test, since it is the linchpin of the guard).
- **JS executor interaction with `RAFScheduler`/HMR:** confirm `installGlobalExecutor()` is idempotent across multiple `render(into:)` calls (multi-root) and survives an HMR re-import without double-installing.
- **`@Sendable` closure capturing `self`:** the component is `@MainActor`; the closure is `@MainActor @Sendable`. Confirm capture of a `@MainActor`-isolated `self` into a `@MainActor @Sendable` async closure compiles cleanly under the WASM cross-compile.
- **Settle iteration cap value:** pick a default that never trips on legitimate chained reruns but catches real cycles.

## Rejected alternatives

- **Async `body` / Suspense (concurrent rendering):** would make the entire diff pipeline async (suspend/resume partial trees, fallback boundaries, tearing, mid-flight prop-change races) — React Concurrent Mode, the hardest problem in the space. No speed gain (RAF already batches), and it pushes complexity onto end users. Rejected.
- **`@Effect` property wrapper (useEffect-shaped):** deepest macro coupling (most fragile under WASM cross-compile), the `self`-capture-in-initializer problem doesn't cleanly compile, and it imports React's most error-prone mental model (the deps array). Rejected.
- **`tasks()` lifecycle method:** keeps `body` pure but decouples effects from the view that consumes them, uses fragile index identity, and is a parallel mechanism rather than a reuse of the handler-collection path. A possible future *escape hatch*, not the primary. Rejected for now.
- **`throws` closure with a framework error sink:** the foundation can't meaningfully handle an error it doesn't understand; would force log-and-swallow. Rejected in favor of non-throwing.
- **Cooperative-by-contract cancellation** (mandatory `guard !Task.isCancelled` + `catch is CancellationError` at every call site): an earlier draft accepted this ceremony and leaned on docs. The Taylor-Otwell review flagged it as a lifecycle concern leaking into user code — a foundation should be correct-by-default. Rejected in favor of the runtime superseded-write guard, which moves the correctness into the bedrock and collapses the call site to the consumer's domain `do/catch`.
- **Naming `.task(id:)`** (SwiftUI parity): `id:` names the mechanism, not the behavior, and is SwiftUI's own most-confused label. **Naming `.task(restartOn:)`:** "restart" reads too heavy (restart *what* — the app?) and over-implies a prior run on first mount. Chosen: **`.task(rerunOn:)`** — lightest action word, its implicit object is unambiguously the braced closure, and it pairs cleanly with bare `.task { }`. A multi-dependency form `.task(rerunOn: [a, b])` works for free under the generic signature, since an `Array` of `Equatable` is itself `Equatable`.
