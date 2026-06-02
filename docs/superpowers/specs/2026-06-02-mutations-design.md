# Swiflow Mutations — Design Spec

> Sub-project #2 of the Swiflow data layer (TanStack-Query/SWR-style). Builds
> directly on the shipped Query Core (`SwiflowQuery`): the typed `Query`
> protocol, `QueryClient` cache, `query()` consumption, prefix+tag
> `invalidate(...)`, and the `RenderObserver` boundary hook.

**Status:** Approved design, ready for implementation plan.
**Date:** 2026-06-02
**Predecessor spec:** `docs/superpowers/specs/2026-06-01-query-core-design.md` (Query Core, shipped). Its §12 lists this sub-project: *"a `Mutation` analogue, optimistic updates with rollback, auto-invalidation of affected query keys/tags on success."*

---

## 1. Goal

Add **writes** to the data layer: a typed, self-describing `Mutation`, fired
imperatively from event handlers, with three declarative capabilities:

1. **Run a write** (`perform`) and track its state (`isPending`/`isSuccess`/`isError`/`data`/`error`).
2. **Optimistic updates** — apply the expected cache result immediately, roll back automatically on failure.
3. **Auto-invalidation** — refresh the queries the write affected, reusing Query Core's `invalidate`.

### The architectural pivot from queries

Queries are **declarative and shared**: observed during `body`, keyed by
`queryKey` in a shared cache, re-run by the `RenderObserver` reconcile path.
Mutations are the opposite on both axes:

- **Local, not shared** — each component instance owns its in-flight/error state. Nothing is keyed globally.
- **Imperative, not observed** — fired from an `onClick` handler, run once, and the resulting state must persist across the re-renders the mutation itself triggers.

So mutations do **not** reuse the `query()` machinery. They get a home that
matches their semantics: per-component reactive state, sibling to `@State`.

### In scope

- `Mutation` protocol (`Input`, `Output`, `perform`, `optimistic`, `invalidations`).
- `@MutationState` macro + `$`-projected `MutationHandle` (the consumption surface).
- Declarative `optimistic()` with automatic snapshot + rollback.
- Declarative `invalidations(input:output:)` running on success.
- `mutate` (fire-and-forget) + `mutateAsync` (awaitable, for side effects) + `reset()`.
- A package-internal cache-write primitive on `QueryClient` (`setQueryData`/`getQueryData`) that the optimistic engine uses.
- Test coverage via the existing `AsyncTestHarness`.

### Out of scope (explicitly deferred)

- Mutation-result caching / dedup / a "mutation cache".
- Retries / backoff (consistent with Query Core's no-auto-retry).
- Lifecycle callbacks on the type (`onMutate`/`onSuccess`/`onError`/`onSettled`) — side effects go at the call site via `mutateAsync`.
- **Public** `getQueryData`/`setQueryData` (no imperative cache-surgery surface yet).
- Queueing / cancelling concurrent mutations (re-entrancy allowed; UIs gate on `isPending`).
- Optimistic helpers beyond `.update` (e.g. `.set`, insert/remove sugar).

---

## 2. Module & dependencies

All new code lands in **`SwiflowQuery`**. New files:

| File | Responsibility |
|---|---|
| `Sources/SwiflowQuery/Mutation.swift` | `Mutation` protocol + default `optimistic`/`invalidations`. |
| `Sources/SwiflowQuery/Invalidation.swift` | `Invalidation` enum. |
| `Sources/SwiflowQuery/OptimisticEdit.swift` | `OptimisticEdit` + `.update` factory (type-erased apply/snapshot). |
| `Sources/SwiflowQuery/MutationState.swift` | `MutationStatus`, `MutationRuntime<M>` (persistent state class), `MutationHandle<M>` (the `$`-projection value). |
| `Sources/SwiflowQuery/MutationMacro.swift` | The `@MutationState` macro **declaration** (`#externalMacro`). |
| `Sources/SwiflowQuery/QueryClient+Cache.swift` | Package-internal `getQueryData`/`setQueryData` + mutation-task registration. |

Modified:

| File | Change |
|---|---|
| `Sources/SwiflowMacrosPlugin/MutationStateMacro.swift` (new) | Macro **implementation** (peer macro). |
| `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` | Register `MutationStateMacro` in `providingMacros`. |
| `Package.swift` | Add `"SwiflowMacrosPlugin"` to the `SwiflowQuery` target's dependencies (so the macro declaration resolves). |
| `Sources/SwiflowQuery/QueryClient.swift` | Mutation in-flight task registry surfaced through `inFlightTasks()`. |

**Dependency direction is preserved.** `SwiflowQuery` already depends on
`Swiflow`. The macro **implementation** lives in the existing
`SwiflowMacrosPlugin` and emits *source text* into the user's module — which
imports `SwiflowQuery` — so emitted references to `MutationHandle`,
`MutationRuntime`, `QueryClient`, and `RenderObserverBox` resolve there, not
in the plugin. No core (`Swiflow`) source changes are required.

---

## 3. Core types

### 3.1 `Mutation` — the self-describing write

Mirrors `Query`: one value carries behavior (`perform`), captured
dependencies (stored properties), and declarations of its effects
(`optimistic`, `invalidations`). `@MainActor`-isolated to match the
single-threaded WASM runtime, so captured dependencies never cross an actor
boundary.

```swift
@MainActor
public protocol Mutation {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    /// Run the write. Cancellation is cooperative via the surrounding Task.
    func perform(_ input: Input) async throws -> Output

    /// Cache edits applied *before* `perform` resolves. The engine snapshots
    /// the prior values, applies these, and rolls them back on failure.
    /// Defaults to none.
    func optimistic(_ input: Input) -> [OptimisticEdit]

    /// What to refresh once `perform` succeeds — a function of input AND the
    /// server's output, so it can target the freshly-created entity.
    /// Defaults to none.
    func invalidations(input: Input, output: Output) -> [Invalidation]
}

public extension Mutation {
    func optimistic(_ input: Input) -> [OptimisticEdit] { [] }
    func invalidations(input: Input, output: Output) -> [Invalidation] { [] }
}
```

Rationale for `Input`/`Output: Sendable`: both cross the `await` in `perform`
inside a `@MainActor` task. `Output` is **not** required `Equatable`
(unlike `Query.Value`) — it is never cached by key nor diffed; it only
populates the handle's `data` for display.

Example:

```swift
struct CreateTodo: Mutation {
    let api: API                                      // dependency, injected at construction

    func perform(_ title: String) async throws -> Todo {
        try await api.post("/todos", title: title)
    }

    func optimistic(_ title: String) -> [OptimisticEdit] {
        // append a draft to the cached list; rolled back automatically on failure
        [.update(TodosList()) { $0 + [Todo.draft(title: title)] }]
    }

    func invalidations(input: String, output: Todo) -> [Invalidation] {
        [.prefix(["todos"]), .tag("todos")]
    }
}
```

### 3.2 `Invalidation`

A declarative target that maps onto Query Core's existing
`invalidate(_:exact:)` and `invalidate(tag:)`.

```swift
public enum Invalidation: Sendable {
    case prefix(QueryKey)   // → client.invalidate(key, exact: false)
    case exact(QueryKey)    // → client.invalidate(key, exact: true)
    case tag(QueryTag)      // → client.invalidate(tag:)
}
```

### 3.3 `OptimisticEdit`

An opaque, type-erased description of one cache edit, constructed from a typed
`Query` so the transform is fully type-checked. The `Query` instance supplies
**both** the cache key (`q.queryKey`) and the value type (`Q.Value`).

```swift
public struct OptimisticEdit {
    let key: QueryKey
    // type-erased: reads current Any?, returns transformed Any (or nil for no-op)
    let apply: (Any?) -> Any?

    /// Transform the cached value of `query`. No-op when the entry has no
    /// value yet (returns nil → engine skips the write and records no snapshot).
    public static func update<Q: Query>(
        _ query: Q,
        _ transform: @escaping (Q.Value) -> Q.Value
    ) -> OptimisticEdit {
        OptimisticEdit(key: query.queryKey) { current in
            guard let value = current as? Q.Value else { return nil }
            return transform(value)
        }
    }
}
```

`.update` covers the common cases — toggle/edit an entity, append/remove in a
cached list. v1 ships only `.update`; `.set` and insert/remove sugar are
deferred (§14).

### 3.4 `MutationStatus` and the handle surface

```swift
public enum MutationStatus: Sendable { case idle, pending, success, error }
```

The `$`-projection (`MutationHandle<M>`, §4) exposes:

```swift
var isIdle: Bool      // status == .idle
var isPending: Bool   // status == .pending
var isSuccess: Bool   // status == .success
var isError: Bool     // status == .error
var data: M.Output?   // last successful output
var error: (any Error)?

func mutate(_ input: M.Input)                              // fire-and-forget
func mutateAsync(_ input: M.Input) async throws -> M.Output // awaitable, for side effects
func reset()                                               // → idle, clears data/error
```

---

## 4. Consumption — `@MutationState` and the `$`-projection

Mutations are per-component reactive state, so they share `@State`'s home and
its exact shape: the declared name holds the *definition*, the `$`-projection
holds the *live reactive handle*.

```swift
@MainActor @Component
final class AddTodo {
    let api: API
    @State var title = ""
    @MutationState var create: CreateTodo      // `create` = the Mutation; `$create` = the handle

    init(api: API) {
        self.api = api
        self.create = CreateTodo(api: api)     // deps injected here, where they're available
    }

    var body: VNode {
        form {
            input(.value($title))
            button("Add") {
                Task {
                    let todo = try await self.$create.mutateAsync(self.title)
                    self.title = ""                      // side effect, co-located with the trigger
                    // e.g. router.navigate(to: todo.id)
                }
            }
        }
        .disabled($create.isPending)
        if $create.isError { p("Couldn't add todo") }
    }
}
```

### Why `$create` (the handle) and not `create.mutate(...)`

This shape is *forced* by Swift + the codebase, and it lands exactly parallel
to `@State`:

- Mutations carry dependencies (`api`), so the `Mutation` must be constructed in `init` (not an attribute argument and not a property initializer that can't see `self`). Therefore `create` must be a settable stored property of the `Mutation` type.
- A property has one type for get and set, so `create` cannot *also* return a `MutationHandle` (a macro accessor can't change the type the way a property wrapper's `wrappedValue` can).
- `@State var title: String` already establishes the idiom: the name is the value, **`$title` is the reactive projection**. `@MutationState var create: CreateTodo` → **`$create` is the reactive handle** is the direct analogue.

### What the macro emits

`@MutationState` is a **peer macro** (no accessor needed — reassigning the
`Mutation` definition is not itself a re-render trigger). For
`@MutationState var create: CreateTodo` it emits, as siblings in the component
class:

```swift
// persistent reactive state — survives across renders with the component instance
private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

// the reactive handle projection
var $create: MutationHandle<CreateTodo> {
    _create_mutationRuntime.wire(
        mutation: create,
        owner: runtimeOwner,                          // private @Component field — in-class access OK
        scheduler: runtimeScheduler,                  // private @Component field — in-class access OK
        client: RenderObserverBox.current as? QueryClient  // captured during render (see §8)
    )
    return MutationHandle(runtime: _create_mutationRuntime)
}
```

Because the projection is a sibling member of the component class, it can read
the **private** `runtimeOwner`/`runtimeScheduler` that `@Component` already
emits — no `@Component` changes, no new enumeration array. The macro reads the
type annotation (`CreateTodo`) exactly as `@State` does to emit
`Binding<T>`.

---

## 5. Data flow — the `mutate` lifecycle

`mutate(_:)` and `mutateAsync(_:)` share one engine path (`MutationRuntime.run`).
The state transitions are identical regardless of which entry point is used.

```
mutate(input) / mutateAsync(input)
   │
   ├─ 1. Apply optimism: for each OptimisticEdit
   │        snapshot = client.getQueryDataErased(edit.key)  // record prior (Any?)
   │        if let next = edit.apply(snapshot) {
   │            client.setQueryData(edit.key, next)          // write + notify observers → instant UI
   │            push (edit.key, snapshot) onto rollback stack
   │        }
   ├─ 2. status = .pending; data/error unchanged; markDirty(owner)
   ├─ 3. output = try await mutation.perform(input)
   │
   ├─ success ─ 4a. status = .success; data = output
   │            5a. for each Invalidation → client.invalidate(...)   // refetch reconciles cache w/ server
   │            6a. markDirty(owner); mutateAsync returns output
   │
   └─ failure ─ 4b. for each (key, prior) on rollback stack (reverse):
   │                    client.setQueryData(key, prior)              // restore + notify
   │            5b. status = .error; error = thrown
   │            6b. markDirty(owner); mutateAsync rethrows
```

Notes:

- The optimistic value stays applied through `perform`; on success the
  `invalidations` refetch overwrites it with server truth (standard SWR — a
  brief reconcile, usually invisible since the optimistic value ≈ the result).
- `mutate` is fire-and-forget: it kicks off `run` and discards the task; the UI
  reacts purely through the handle's published state. `mutateAsync` awaits the
  same `run` and returns/rethrows so side effects sequence with `async`/`await`
  at the call site.
- The driving task is registered with the client (§8.3) so the existing
  `AsyncTestHarness.settle()` awaits it.

---

## 6. Optimistic updates & rollback

The developer declares *what the cache should look like*; the engine owns
snapshot/apply/rollback. This deletes the TanStack footgun class (forgetting
to snapshot in `onMutate` or restore in `onError`).

- **Snapshot:** the engine reads `client.getQueryData(key)` (type-erased `Any?`) *before* applying each edit, and stashes `(key, prior)`. There is no developer-visible snapshot/context object.
- **Apply:** `setQueryData(key, transformed)` writes the entry's value and runs the existing notify path so mounted `query()` observers re-render with the optimistic value immediately.
- **No-op safety:** `.update` returns `nil` from `apply` when the targeted entry has no cached value (nothing on screen reads it yet). The engine skips the write and records no snapshot — nothing to roll back.
- **Rollback:** on `perform` failure, the engine restores each `(key, prior)` in reverse order via `setQueryData` (including `prior == nil`, which clears a value the edit had seeded — though v1 `.update` never seeds).

Multiple edits per mutation are supported (e.g. update a list *and* a detail
entry); each is independently snapshotted and rolled back.

---

## 7. Auto-invalidation

On success, the engine evaluates `mutation.invalidations(input:output:)` and
dispatches each `Invalidation` to the **existing** client API:

| `Invalidation` | Query Core call |
|---|---|
| `.prefix(key)` | `client.invalidate(key, exact: false)` |
| `.exact(key)`  | `client.invalidate(key, exact: true)` |
| `.tag(t)`      | `client.invalidate(tag: t)` |

This reuses the shipped prefix-cascade + tag machinery verbatim: mounted
observers of matching keys refetch, reconciling the cache with the server.
Because `invalidations` receives `output`, a create can target the new id:
`invalidations(input:output:) -> [.exact(["todos", .int(output.id)]), .prefix(["todos"])]`.

---

## 8. Wiring — owner, scheduler, client

The handle needs three references to function: the `owner` and `scheduler`
(to `markDirty` and trigger re-render) and the `QueryClient` (to read/write the
cache and invalidate).

### 8.1 Owner + scheduler (always available post-mount)

`@Component` already emits `private weak var runtimeOwner` and
`private var runtimeScheduler`, bound once per instance at mount via
`bind(owner:scheduler:)` (called from `wireStateAndRestore` during the diff).
The macro-emitted `$create` projection is an in-class sibling, so it reads
those private fields directly — identical to how `@State`'s `didSet` reads them
to `markDirty`.

### 8.2 Client (captured during render)

`QueryClient` lives above `Swiflow`, so it cannot be a typed field on the core
`@Component`. Instead — exactly as `query()` does — the handle captures it from
the type-erased `RenderObserverBox.current as? QueryClient`, which is the
installed client during any render/diff. The `$create` projection caches the
client into `_create_mutationRuntime` whenever it is evaluated within a render
(`RenderObserverBox.current != nil`); the cache is only overwritten with a
non-nil value.

**Constraint:** `$create` must be referenced in `body` at least once before
`mutate` fires, so the client is captured. This is the universal pattern —
components show `$create.isPending` (disable) and/or `$create.isError`
(message). If `mutate`/`mutateAsync` is invoked while unwired (client never
captured), the engine emits a `swiflowDiagnostic` and runs `perform` **without**
optimism or invalidation (the write still happens; only the cache-reconcile is
skipped). A future hardening (deferred, §14) can wire the client at mount via a
`@Component`-emitted mutation-cell array if this constraint proves limiting.

### 8.3 Mutation task registration (for tests + settle)

`AsyncTestHarness.settle()` awaits `renderer.queryClient.inFlightTasks()`. The
engine registers its driving task with the client so `settle()` blocks on
in-flight mutations too:

```swift
// QueryClient (package surface)
package func registerMutationTask(_ task: Task<Void, Never>)   // stored; auto-pruned on completion
package func inFlightTasks() -> [Task<Void, Never>]            // now includes mutation tasks
```

`run` wraps its work in a `Task<Void, Never>` (the awaitable result for
`mutateAsync` is bridged separately, see §5), registers it, and removes it on
completion.

---

## 9. Error handling

- `perform` throwing → optimistic rollback (§6) → `status = .error`, `error` set, `isPending` false. The error surfaces through the handle for display.
- **No auto-retry** (consistent with Query Core). Retry = call `mutate` again.
- `mutateAsync` rethrows so call-site `do/catch` works; the handle's `error` is also populated, so fire-and-forget callers that don't catch still get a displayable error.
- `reset()` returns the handle to `.idle` and clears `data`/`error` (e.g. after the user dismisses an error).

---

## 10. Concurrency & re-entrancy

- All mutation code is `@MainActor`; `perform` is the only suspension point.
- A second `mutate` while one is pending is **allowed**; both run. State reflects the last to resolve. Optimistic snapshots are independent per call, restored on each call's own failure. v1 does **not** queue or cancel — UIs gate re-entry with `.disabled($create.isPending)`, which is the documented pattern. (Noted as a known limitation; queue/cancel deferred to §14.)

---

## 11. Required Query Core extension (package-internal)

```swift
// QueryClient+Cache.swift — NOT public in v1
extension QueryClient {
    /// Current cached value at `key`, or nil if absent / type mismatch.
    package func getQueryData<V>(_ key: QueryKey, as type: V.Type) -> V?

    /// Type-erased read used by the optimistic engine (it holds Any? snapshots).
    package func getQueryDataErased(_ key: QueryKey) -> Any?

    /// Write `value` into the entry at `key` (creating nothing if absent is
    /// acceptable for v1 — see note) and run the existing notify/markDirty
    /// path so mounted observers re-render. Does NOT mark the entry fresh in a
    /// way that suppresses a subsequent invalidation refetch.
    package func setQueryData(_ key: QueryKey, _ value: Any?)
}
```

Implementation reuses the existing per-entry storage and the `notify` path
(prune-on-nil-owner semantics unchanged). `setQueryData` on a key with **no**
entry is a no-op in v1 (optimistic edits target on-screen queries, which have
live entries); seeding absent entries is deferred.

---

## 12. Testing strategy

All via the existing `AsyncTestHarness` (its `settle()` already awaits
`queryClient.inFlightTasks()`, which §8.3 extends to include mutation tasks).
A test `Mutation` uses an injected closure/`actor`-free fake like the existing
`QueryIntegrationTests.UserByID(load:)` pattern.

Unit (engine, no component):
- success → `data` set, `isSuccess`, `isPending` false.
- failure → `error` set, `isError`, `isPending` false; no `data` overwrite.
- `reset()` → `.idle`, `data`/`error` cleared.
- `mutateAsync` returns `output` on success, rethrows on failure.
- `isPending` is true between call and resolution (gate via a `Gate`-style await, as in Query Core's `supersedingFetchSurvivesStaleCompletion`).

Integration (mounted component + a live `query()`):
- optimistic value visible on an observing query **before** `perform` resolves.
- rollback restores the prior query value on failure.
- `invalidations` triggers a refetch of a mounted observer on success (assert via a fetch counter, like `invalidateRefetchesMountedObserver`).
- side-effect path: `mutateAsync` resolves, then a `@State` write (`title = ""`) is reflected after `flush()`.
- re-render: `isPending` toggles drive the `.disabled(...)` attribute in the rendered tree.

Macro:
- a golden expansion test for `@MutationState` (emitted `_*_mutationRuntime` + `$name` projection), paralleling existing `@State`/`@Component` macro tests.

---

## 13. Required changes summary

**New (`SwiflowQuery`):** `Mutation.swift`, `Invalidation.swift`,
`OptimisticEdit.swift`, `MutationState.swift`, `MutationMacro.swift`,
`QueryClient+Cache.swift`.

**Modified:**
- `SwiflowQuery/QueryClient.swift` — mutation-task registry surfaced through `inFlightTasks()`.
- `SwiflowMacrosPlugin/` — add `MutationStateMacro.swift`; register it in `SwiflowMacrosPlugin.swift`.
- `Package.swift` — add `"SwiflowMacrosPlugin"` to the `SwiflowQuery` target deps.

**No `Swiflow` (core) source changes.** The `RenderObserver` hook and the
`@Component`-emitted `runtimeOwner`/`runtimeScheduler` are reused as-is.

---

## 14. Non-goals / deferred

- Mutation-result cache / dedup / mutation history.
- Retries / backoff.
- Lifecycle callbacks on the `Mutation` type.
- Public `getQueryData`/`setQueryData` imperative cache surgery.
- Concurrent-mutation queueing / cancellation.
- Optimistic `.set` and insert/remove helpers beyond `.update`.
- Mount-time client wiring via a `@Component` mutation-cell array (only if the §8.2 "reference `$create` in body" constraint proves limiting).
- Seeding cache entries that have no live observer from `setQueryData`.

---

## 15. Design rationale — key forks and why

1. **Self-describing `Mutation` type (not closure-at-call-site).** Same identity as `Query`: deps + behavior + declared effects in one reusable, unit-testable value. The invalidation declaration is `(input, output) -> [Invalidation]` (not a static list) specifically so writes can target the server-assigned id.
2. **`@MutationState` + `$`-projection (not a `query()`-style body method).** Mutation state is local and imperative, the opposite of a query's shared declarative cache. Routing it through a `mutation()` body method would force **call-site positional identity** to fake per-component state — a brand-new fragility class the codebase doesn't have. `@MutationState` says exactly what it is: local reactive state, sibling to `@State`, with stable per-instance identity for free.
3. **Declarative `optimistic()` with engine-owned rollback (not imperative `onMutate`/`onError` hooks).** Turns the most error-prone part of mutations into a typed, declarative statement built on the existing typed `Query`. The imperative escape hatch (public `setQueryData`) stays deferred until a real case needs surgery the declarative form can't express.
4. **`mutate` / `mutateAsync` pair; side effects at the call site (not lifecycle callbacks).** Structured concurrency reads top-to-bottom where the action fires, and avoids re-introducing the callback model that declarative optimism just removed.
5. **Macro path forced by Swift constraints, landing parallel to `@State`.** Dependencies-in-`init` ⇒ `create` is the stored `Mutation`; one-type-per-property ⇒ the handle is the `$`-projection. The result is *more* consistent with `@State`, and needs zero core changes.
