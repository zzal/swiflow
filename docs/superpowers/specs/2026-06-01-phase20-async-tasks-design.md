# Phase 20 — Async Task Effects (`.task` / `.task(rerunOn:)`)

**Status:** Draft (awaiting review)
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
      let u = try await fetchUser(userID)
      guard !Task.isCancelled else { return }
      user = .success(u)
    } catch is CancellationError {
      // superseded — ignore
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

Plus the `AsyncTestHarness` needed to test all of the above deterministically, and the `JavaScriptEventLoop` wiring needed to make it work in the browser at all.

## Scope

**In:**
- `.task { }` and `.task(rerunOn:)` modifiers on `VNode`, collected during diff like `.on(.click)` handlers.
- Diff-integrated task lifecycle: start on mount, cancel+restart on `rerunOn` change, cancel on unmount — riding the existing node lifecycle, no parallel machinery.
- A task registry/runner that tracks spawned `Task` handles (for cancellation in production, for `await` in tests).
- Cooperative cancellation + a **dead-component write guard** (a `markDirty` on an unmounted component is a no-op).
- `JavaScriptEventLoop.installGlobalExecutor()` wired into the web bootstrap (`Swiflow.render(into:)`), and the `JavaScriptEventLoop` product added to the `SwiflowWeb` target.
- `AsyncTestHarness` + `settle()` in `SwiflowTesting`, with a controllable IO stub pattern and a settle iteration cap.
- A worked fetch example.
- Documentation covering the sharp edges (purity story, restart semantics, the stale-write race).
- Unit/integration tests for lifecycle, rerun, cancellation, and the dead-component guard.

**Explicitly out (separate brainstorm or not pursued):**
- The data-fetching / caching library itself: `QueryClient`, `QueryState<T>`, caching, dedup, invalidation, mutations, persistence.
- Any HTTP/`fetch` wrapper. (`fetchUser` in examples is hand-rolled JavaScriptKit.)
- Async `body` / Suspense / concurrent rendering (rejected — see below).
- `throws` task closures with a framework error sink (rejected — see below).
- An `@Effect` property wrapper or a `tasks()` lifecycle method (rejected — see below).

## API surface

A new modifier on the `VNode` DSL, alongside `.on(...)`:

```swift
public extension VNode {
    /// Run once when this node mounts; cancel when it unmounts. Never restarts.
    func task(_ body: @MainActor @Sendable @escaping () async -> Void) -> VNode

    /// Run when this node mounts; cancel and re-run whenever `rerunOn` changes
    /// between renders; cancel when it unmounts.
    func task<ID: Equatable>(
        rerunOn id: ID,
        _ body: @MainActor @Sendable @escaping () async -> Void
    ) -> VNode
}
```

- The closure is **non-throwing** `@MainActor @Sendable () async -> Void`. Errors are handled inside the closure by the consumer (see Semantics → Errors).
- `rerunOn` requires `Equatable`; restart is decided by `!=` against the prior render's value.
- Multiple `.task`s may decorate one node; they are identified by declaration order on that node (the "stable slot" rule below).

## Semantics

### Lifecycle & identity
Tasks ride the diff's existing node create / update / remove signals — the same path `.on(.click)` handlers already use.

- **Node created (mount)** → start each task on the node.
- **Node persists (re-render, same position/type/key):**
  - `.task { }` → leave running, never restart.
  - `.task(rerunOn: v)` → compare `v` to the prior render's value. Equal → leave running. Changed → cancel the running task, start fresh.
- **Node removed (unmount), including via owning component unmount** → cancel each task on the node.

**Identity** = the mounted node the modifier decorates × the task's declaration slot on that node. **Stable-slot rule:** do not conditionally vary the *number* of `.task`s on a single node — slot indices must be stable across renders. This is the same constraint handlers/attributes already carry, and is documented as such.

Anchoring to the node (not the component) is a deliberate choice: it is a direct reuse of the diff, and a component unmount cancels every task in its subtree for free because the diff already removes those nodes.

### Cancellation & the stale-write race
Cancellation is cooperative (`Task.cancel()`); rerun is **latest-wins** (cancel in-flight, start new). The sharp edge is a cancelled task that ignores cancellation and resumes *after* its replacement, clobbering newer state. Two-layer defense:

1. **Cooperative bail (consumer contract):** `guard !Task.isCancelled else { return }` before any state write, and treat `CancellationError` as a no-op. This is the documented, demonstrated pattern.
2. **Dead-component write guard (framework):** a late write to `@State` on an unmounted component must be a `markDirty` no-op. Phase 20 verifies the scheduler already ignores dirty marks for unmounted components and hardens it if not.

The foundation cannot *prevent* a non-cooperative closure from writing (writes go straight through `@State`), so this is cooperative-by-contract plus loud documentation. The future query library will encapsulate the correct pattern so end users rarely hand-write it.

### Errors
The closure is non-throwing. The framework has no notion of what an error *means* (no `QueryState`, no `.failure`), so catching it could only log-and-swallow — the silent-failure anti-pattern. Forcing the `catch` at the call site puts error handling where the state lives, and matches SwiftUI's `.task`. The cost — hand-written `do/catch` in the raw API — is accepted; the query layer is what later makes it ergonomic.

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
| `.task` / `.task(rerunOn:)` modifier | `Swiflow` | `DSL/Modifiers.swift` (new `Attribute`-style case), `VNode.swift` |
| Task collection + lifecycle (start/rerun/cancel) | `Swiflow` | `Diff/Diff.swift` (ride node create/update/remove) |
| Task registry / runner | `Swiflow` | new file, scheduler-adjacent (`Reactivity/`) |
| Dead-component write guard | `Swiflow` | `Reactivity/Scheduler.swift` (+ `SyncScheduler`) — verify/harden |
| JS executor install + dependency | `SwiflowWeb` | `SwiflowWeb.swift` (`render(into:)`), `Package.swift` |
| `AsyncTestHarness` + `settle()` | `SwiflowTesting` | new `AsyncTestHarness.swift`, reuse `TestRenderer` |
| Worked example | `examples/` | a fetch demo component |

`SwiflowWeb` changes are otherwise minimal: tasks mark state dirty, and `RAFScheduler` already batches dirty components per frame.

## Documentation requirements

A chunk of this primitive's cons are *legibility* cons, so docs are load-bearing (not an afterthought). The docs must explicitly cover:
- **The purity story:** the `.task` closure is *declared* in `body` but *runs later*, owned by the runtime on `@MainActor` — it is not executed during render. (`body` stays pure.)
- **Restart semantics:** `rerunOn` restarts (cancel + fresh start) on `!=`; bare `.task` never restarts; both cancel on unmount.
- **The stale-write race + the cooperative-bail pattern** (`guard !Task.isCancelled`, treat `CancellationError` as no-op).
- **The stable-slot rule** for multiple tasks on one node.

## Testing strategy

- **Lifecycle:** task starts exactly once on mount; cancels exactly once on unmount (mirrors the Trap 7 component-lifecycle test in `examples/EdgeCases`).
- **Rerun:** changing `rerunOn` cancels the prior task and starts a new one; unchanged value does not.
- **Latest-wins / stale-write:** a slow prior run that resolves after a newer run does not clobber newer state.
- **Dead-component guard:** a task resolving after its component unmounts does not crash and does not mark dirty.
- **`settle()` fixed point:** a task that triggers a `rerunOn` change is driven to quiescence; a runaway cycle hits the iteration cap and fails cleanly.
- **Browser smoke (Playwright):** the worked example actually resumes a `Task` and updates the DOM — the regression guard for the `JavaScriptEventLoop` wiring. (Per the Playwright-CI-gap note, run manually after this runtime change.)

## Risks & open questions

- **JS executor interaction with `RAFScheduler`/HMR:** confirm `installGlobalExecutor()` is idempotent across multiple `render(into:)` calls (multi-root) and survives an HMR re-import without double-installing.
- **`@Sendable` closure capturing `self`:** the component is `@MainActor`; the closure is `@MainActor @Sendable`. Confirm capture of a `@MainActor`-isolated `self` into a `@MainActor @Sendable` async closure compiles cleanly under the WASM cross-compile (this is the area that has bitten macro isolation before — verify early).
- **Settle iteration cap value:** pick a default that never trips on legitimate chained reruns but catches real cycles.

## Rejected alternatives

- **Async `body` / Suspense (concurrent rendering):** would make the entire diff pipeline async (suspend/resume partial trees, fallback boundaries, tearing, mid-flight prop-change races) — React Concurrent Mode, the hardest problem in the space. No speed gain (RAF already batches), and it pushes complexity onto end users. Rejected.
- **`@Effect` property wrapper (useEffect-shaped):** deepest macro coupling (most fragile under WASM cross-compile), the `self`-capture-in-initializer problem doesn't cleanly compile, and it imports React's most error-prone mental model (the deps array). Rejected.
- **`tasks()` lifecycle method:** keeps `body` pure but decouples effects from the view that consumes them, uses fragile index identity, and is a parallel mechanism rather than a reuse of the handler-collection path. A possible future *escape hatch*, not the primary. Rejected for now.
- **`throws` closure with a framework error sink:** the foundation can't meaningfully handle an error it doesn't understand; would force log-and-swallow. Rejected in favor of non-throwing.
- **Naming `.task(id:)`** (SwiftUI parity): `id:` names the mechanism, not the behavior, and is SwiftUI's own most-confused label. **Naming `.task(restartOn:)`:** "restart" reads too heavy (restart *what* — the app?) and over-implies a prior run on first mount. Chosen: **`.task(rerunOn:)`** — lightest action word, its implicit object is unambiguously the braced closure, and it pairs cleanly with bare `.task { }`. A multi-dependency form `.task(rerunOn: [a, b])` works for free under the generic signature, since an `Array` of `Equatable` is itself `Equatable`.
