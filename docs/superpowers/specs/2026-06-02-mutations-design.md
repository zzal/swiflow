# Swiflow Mutations — Design Spec

> Sub-project #2 of the Swiflow data layer (TanStack-Query/SWR-style). Builds
> directly on the shipped Query Core (`SwiflowQuery`): the typed `Query`
> protocol, `QueryClient` cache, `query()` consumption, prefix+tag
> `invalidate(...)`, and the `RenderObserver` boundary hook.

**Status:** ✅ **Implemented & shipped** (11-task TDD execution, branch `mutations`). **Rev 4** — reconciled the spec to the as-built code: the engine is a synchronous `beginOptimistic` + async `finish` split (not one `run`) so optimism is applied on the caller's tick (§5.1); the emitted `bind` calls the public `_currentRenderQueryClient()` accessor rather than the `package` `RenderObserverBox` directly (§4/§8.2); the unwired path uses `assertionFailure`+degraded (§8.2); `Invalidation` is `Equatable`. `SwiflowQuery` stayed on the default language mode (v6 was not required to build). **Rev 3** — confirmation pass closed the last gap: the B1 mount-wiring needs a one-line `TestRenderer.init` ordering fix (install the client before the root `wireState`). **Rev 2** — incorporated the swift-innovator review (B1 mount-time client wiring pulled into v1; B2 `run`→`Result` engine + `mutateAsync` bridge + cancellation contract; B3 `setQueryData` cancels in-flight + bumps generation).
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
- **Mount-time client wiring** — `@Component` scans `@MutationState` and wires the `QueryClient` into each mutation runtime at mount, so a mutation is *never* unwired regardless of whether `body` reads its handle (B1).
- Declarative `optimistic()` with automatic snapshot + rollback.
- Declarative `invalidations(input:output:)` running on success.
- `mutate` (fire-and-forget, the common path) + `mutateAsync` (awaitable, for side effects) + `reset()`.
- A package-internal cache-write primitive on `QueryClient` (`setQueryData`/`getQueryData`) that cancels any in-flight fetch + bumps the entry generation so optimistic values survive concurrent SWR revalidation (B3).
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
| `Sources/SwiflowMacrosPlugin/MutationStateMacro.swift` (new) | `@MutationState` peer-macro **implementation** (emits the backing runtime + `$name` projection). |
| `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` | Scan members for `@MutationState` (alongside the existing `@State`/`@MacroState` scan at `ComponentMacro.swift:84-89`); emit mount-time client wiring into `bind(owner:scheduler:)` (B1, §8.2). |
| `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` | Register `MutationStateMacro` in `providingMacros`. |
| `Package.swift` | Add `"SwiflowMacrosPlugin"` to the `SwiflowQuery` target's dependencies (so the macro declaration resolves). **Also confirm the language-mode**: `SwiflowQuery` is currently the one target *without* `.swiftLanguageMode(.v6)`; adding a macro dependency may surface a mismatch — set it to match if the build complains. |
| `Sources/SwiflowQuery/QueryClient.swift` | Token-based mutation in-flight task registry surfaced through `inFlightTasks()`; `setQueryData` cancel+generation-bump semantics (§11). |
| `Sources/SwiflowTesting/TestRenderer.swift` | **Ordering fix (B1):** set `RenderObserverBox.current = queryClient` *before* the root `wireState(on:scheduler:)` call in `init`, so mount-time mutation wiring on the root component-under-test captures the client (it's currently set ~5 lines *after* `wireState` — `TestRenderer.swift:41` vs `:46`). Without this, a root `@MutationState` is wired with a `nil` client. |

**Dependency direction is preserved.** `SwiflowQuery` already depends on
`Swiflow`. The macro **implementations** live in the existing
`SwiflowMacrosPlugin` and emit *source text* into the user's module — which
imports `SwiflowQuery` — so emitted references to `MutationHandle`,
`MutationRuntime`, `QueryClient`, and `RenderObserverBox` resolve there, not in
the plugin.

**No `Swiflow` *core/Diff* source changes** (the `RenderObserver` hook,
`runtimeOwner`/`runtimeScheduler`, and `bind`/`wireStateAndRestore` are reused
as-is). Two non-core changes are required: the `@Component` **macro**
(`ComponentMacro`, in the plugin) learns to scan `@MutationState`, and
`SwiflowTesting/TestRenderer` needs the one-line ordering fix above. The macro's
mount-wiring emission references `QueryClient`/`RenderObserverBox` **only when
the component actually declares a `@MutationState`** — and such a component
necessarily imports `SwiflowQuery`, so the references resolve. Components
without mutations emit byte-identical `bind` bodies to today and never name a
`SwiflowQuery` type, so nothing that doesn't use mutations is affected.

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
public enum Invalidation: Equatable, Sendable {   // Equatable: handy for tests
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

Note the deliberate constraint asymmetry: an `OptimisticEdit`'s value is the
target query's `Q.Value`, which is `Equatable & Sendable` by `Query`'s own
contract (`Query.swift:14`). A `Mutation`'s `Output` (§3.1) is only `Sendable`.
That's intentional — `Output` is display-only, while the edit's value flows
into a cache entry whose stored `valuesEqual` witness was captured from
`Q.Value` and so must remain that exact concrete type (the type-erasure
contract, §11).

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

**`status` and `data`/`error` are orthogonal** (the same reasoning that made
`QueryState` a struct, not an enum). A subsequent failed `mutate` sets
`status = .error` and populates `error` but **retains the prior `data`** from
the last success — matching queries' SWR semantics. `isSuccess` is therefore
`status == .success`, *not* `data != nil` (the two diverge after a failure that
follows a success). `reset()` is the only thing that clears `data`.

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
            // Common path — fire-and-forget. The UI reacts purely through the
            // handle's published state; no Task, no await.
            button("Add") { self.$create.mutate(self.title) }
        }
        .disabled($create.isPending)
        if $create.isError { p("Couldn't add todo") }
    }
}
```

When a success needs a *side effect* that isn't a cache write (clear the form,
navigate, close a dialog), reach for `mutateAsync` at the call site — the
escape hatch, not the default:

```swift
button("Add") {
    Task {
        let todo = try await self.$create.mutateAsync(self.title)
        self.title = ""                      // side effect, co-located with the trigger
        // e.g. router.navigate(to: todo.id)
    }
}
```

> Lead with `mutate`; it covers the majority of buttons. The `Task { try await … }`
> ceremony of `mutateAsync` is only paid when you actually sequence a side
> effect. (Whether the event-handler closure could itself be `async` — dropping
> the `Task {}` wrapper — is a separate framework question, out of scope here.)

### Why `$create` (the handle) and not `create.mutate(...)`

This shape is *forced* by Swift + the codebase, and it lands exactly parallel
to `@State`:

- Mutations carry dependencies (`api`), so the `Mutation` must be constructed in `init` (not an attribute argument and not a property initializer that can't see `self`). Therefore `create` must be a settable stored property of the `Mutation` type.
- A property has one type for get and set, so `create` cannot *also* return a `MutationHandle` (a macro accessor can't change the type the way a property wrapper's `wrappedValue` can).
- `@State var title: String` already establishes the idiom: the name is the value, **`$title` is the reactive projection**. `@MutationState var create: CreateTodo` → **`$create` is the reactive handle** is the direct analogue.

### What the macros emit

Two macros cooperate. The naming convention for the backing field
(`_<name>_mutationRuntime`) is shared between them.

**`@MutationState` (peer macro).** No accessor needed — reassigning the
`Mutation` definition is not itself a re-render trigger. For
`@MutationState var create: CreateTodo` it emits, as siblings in the component
class:

```swift
// persistent reactive state — survives across renders with the component instance.
// (owner / scheduler / client are injected at mount by @Component's bind, §8.)
private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

// the reactive handle projection — a cheap value wrapping the persistent runtime
// plus a snapshot of the current `Mutation` (so a reassigned `create` is picked up).
var $create: MutationHandle<CreateTodo> {
    MutationHandle(runtime: _create_mutationRuntime, mutation: create)
}
```

The projection does **no** wiring — it just reads. All three references the
runtime needs (`owner`, `scheduler`, `client`) are injected once at mount (§8.2),
so the handle works even if `body` never reads it. The macro reads the type
annotation (`CreateTodo`) exactly as `@State` does to emit `Binding<T>`.

**`@Component` (member macro, extended).** It already scans members for `@State`
to build `stateCells`. It additionally scans for `@MutationState` and, for each,
appends a wiring statement to the `bind(owner:scheduler:)` body it emits:

```swift
func bind(owner: AnyComponent, scheduler: Scheduler) {
    self.runtimeOwner = owner
    self.runtimeScheduler = scheduler
    // emitted once per @MutationState property, ONLY when the class has one.
    // `_currentRenderQueryClient()` is the public accessor over the `package`
    // RenderObserverBox (the box itself is unreachable from a user module):
    _create_mutationRuntime.wire(
        owner: owner,
        scheduler: scheduler,
        client: _currentRenderQueryClient()
    )
}
```

`bind` runs at mount inside the render pass (it's called from
`wireStateAndRestore`, invoked from the diff), so `RenderObserverBox.current`
*is* the installed `QueryClient` at that moment (§8.2). Because the wiring line
is emitted only for classes that declare a `@MutationState` — which necessarily
import `SwiflowQuery` — the `QueryClient`/`RenderObserverBox` references always
resolve, and mutation-free components emit an unchanged `bind`.

**Naming-convention coupling.** The two macros agree on the backing-field name
`_<name>_mutationRuntime` by convention — `@MutationState` emits it,
`@Component` reconstructs it from the property name when emitting the `wire`
call. This is the same *class* of coupling `@State`/`@Component` already have
(via the `stateCells` array + the `runtimeOwner`/`runtimeScheduler` field
names), so it is not new fragility, but it is real: if the conventions drift the
failure is an "unresolved identifier" in *user* code. Two implementation shapes
are acceptable, decided in the plan: **(a)** inline per-property `wire(...)`
lines in `bind` (simplest; fine for the typical 1–2 mutations per component), or
**(b)** a macro-emitted typed descriptor array — `static let mutationRuntimes:
[any AnyMutationWireable]` built by `@Component` (parallel to `stateCells`),
iterated by `bind`. (b) is more robust and scales to N mutations without N
emitted lines; it still references the backing field inside each descriptor, so
it does not *eliminate* the convention, only localizes and types it. Recommended
default: **(b)**, for parity with the proven `stateCells` mechanism.

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
- The driving task is registered with the client (§8.3) so the existing
  `AsyncTestHarness.settle()` awaits it.

### 5.1 The engine: synchronous `beginOptimistic` + async `finish`

> **As-built (rev 4).** During implementation, Task 6 established that an
> optimistic write must land **synchronously** with `mutate` — synchronous code
> right after `mutate`, and the very next render, must see the optimistic value
> with no microtask gap. So the single `run` was split into a synchronous
> prologue and an async remainder. The invariants are unchanged: the async half
> **never throws** (returns a `Result`), so `.error` is set in exactly one place
> and `mutateAsync` rethrows the very same stored error.

`beginOptimistic` runs on the caller's tick (inside `mutate`/`mutateAsync`,
*not* the spawned task): it applies the optimistic edits and enters `.pending`,
returning the per-call rollback stack. `finish` is the async remainder
(`perform` → success/invalidate or failure/rollback).

```swift
@MainActor
final class MutationRuntime<M: Mutation> {
    // published: status, data, error; wired at mount: owner, scheduler, client

    /// Synchronous prologue: snapshot+apply optimistic edits, enter `.pending`,
    /// markDirty. Returns the per-call rollback stack. (Unwired client →
    /// `assertionFailure` + no optimism; the write still runs in `finish`.)
    func beginOptimistic(_ input: M.Input, _ mutation: M) -> [(key: QueryKey, prior: Any?)] {
        var rollback: [(key: QueryKey, prior: Any?)] = []
        if let client {
            for edit in mutation.optimistic(input) {
                let prior = client.getQueryDataErased(edit.key)
                if let next = edit.apply(prior) { client.setQueryData(edit.key, next); rollback.append((edit.key, prior)) }
            }
        } else { assertionFailure("no QueryClient wired") }
        status = .pending; markDirty()
        return rollback
    }

    /// Async remainder. Does NOT throw. The `mutation` is passed in by the
    /// handle (which snapshots the current `create`, §4), not stored here.
    func finish(_ input: M.Input, _ mutation: M,
                _ rollback: [(key: QueryKey, prior: Any?)]) async -> Result<M.Output, any Error> {
        let result: Result<M.Output, any Error>
        do    { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }
        switch result {
        case .success(let out):
            status = .success; data = out
            if let client { for inv in mutation.invalidations(input: input, output: out) { dispatch(inv, client) } }
        case .failure(let err):
            if let client { for r in rollback.reversed() { client.setQueryData(r.key, r.prior) } }
            status = .error; error = err
        }
        markDirty()
        return result
    }
}

@MainActor
struct MutationHandle<M: Mutation> {
    let runtime: MutationRuntime<M>
    let mutation: M                                       // snapshot of `create` at $-access (§4)

    func mutate(_ input: M.Input) {                       // fire-and-forget
        let rt = runtime, m = mutation
        let rollback = rt.beginOptimistic(input, m)       // SYNCHRONOUS: optimism + pending
        rt.register { _ = await rt.finish(input, m, rollback) }
    }

    func mutateAsync(_ input: M.Input) async throws -> M.Output {
        let rt = runtime, m = mutation
        let rollback = rt.beginOptimistic(input, m)       // SYNCHRONOUS: optimism + pending
        let task = Task { await rt.finish(input, m, rollback) }   // typed result
        rt.register { _ = await task.value }                       // Void task for settle()
        switch await task.value {
        case .success(let out): return out
        case .failure(let err): throw err               // same error already stored in `.error`
        }
    }
}
```

Why two task handles in `mutateAsync`: `inFlightTasks()` is typed
`[Task<Void, Never>]`, so the result-bearing `Task<Result<…>>` cannot be
registered directly — a `Void` wrapper that awaits it is what `settle()` blocks
on. `runtime.register` wraps the client's token-keyed registry (§8.3).

**`settle()` ordering.** `register(...)` and the synchronous `beginOptimistic`
(which sets `.pending` + `markDirty`) both run before the spawned task's first
suspension (`perform`'s `await`), so a test that calls `settle()` immediately
after `mutate` observes a non-empty in-flight set and the pending/optimistic
state on the next `flush()`. No race.

---

## 6. Optimistic updates & rollback

The developer declares *what the cache should look like*; the engine owns
snapshot/apply/rollback. This deletes the TanStack footgun class (forgetting
to snapshot in `onMutate` or restore in `onError`).

- **Snapshot:** the engine reads `client.getQueryDataErased(key)` (type-erased `Any?`) *before* applying each edit, and stashes `(key, prior)`. There is no developer-visible snapshot/context object.
- **Apply:** `setQueryData(key, transformed)` writes the entry's value, **cancels any in-flight fetch for that key and bumps the entry generation** (so a concurrent SWR revalidation that resolves later cannot clobber the optimistic value — B3, §11), and runs the existing notify path so mounted `query()` observers re-render with the optimistic value immediately.
- **No-op safety + observability:** `.update` returns `nil` from `apply` when the targeted entry has no cached value (nothing on screen reads it yet). The engine skips the write and records no snapshot — nothing to roll back. Because a silently-vanished optimistic edit is hard to debug, the engine emits a `swiflowDiagnostic` **in DEBUG builds** when an `.update` finds no entry (S1).
- **Rollback:** on `perform` failure, the engine restores each `(key, prior)` in reverse order via `setQueryData` (including `prior == nil`, which clears a value the edit had seeded — though v1 `.update` never seeds).

Multiple edits per mutation are supported (e.g. update a list *and* a detail
entry); each is independently snapshotted and rolled back.

**Expressiveness limit (v1).** `.update`'s transform receives only the *target*
query's current value (`(Q.Value) -> Q.Value`). An optimistic edit that must
*read another query* to compute its new value (e.g. derive a total from a
separate aggregate query) cannot be expressed declaratively in v1; that needs
the deferred public `setQueryData` escape hatch (§14). Documented so it doesn't
surprise.

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

### 8.1 Owner + scheduler (injected at mount)

`bind(owner:scheduler:)` (emitted by `@Component`, called from
`wireStateAndRestore` during the diff) already receives the `owner` and
`scheduler`. The extended `bind` (§4) passes them straight into each mutation
runtime's `wire(owner:scheduler:client:)` at mount — the runtime caches them,
exactly once, alongside the client (§8.2). The `$create` projection therefore
does no wiring; it just wraps the already-wired runtime. (This is the same
`owner`/`scheduler` pair `@State`'s `didSet` uses to `markDirty`; the runtime
calls `scheduler.markDirty(owner)` on every state transition in §5.1.)

### 8.2 Client (wired at mount — B1)

`QueryClient` lives above `Swiflow`, so it cannot be a typed field on the core
`@Component`. But it **is** reachable at mount through the same type-erased seam
`query()` uses: `RenderObserverBox.current as? QueryClient`.

> **As-built note:** `RenderObserverBox` is `package`, so it is unreachable from
> a *user* module where the `@Component`-emitted `bind` lives. The macro
> therefore emits a call to the public accessor `_currentRenderQueryClient()`
> (defined in `SwiflowQuery`, which *can* read the `package` box), not a direct
> `RenderObserverBox.current` reference. Same seam, exported through one public
> function.

The critical fact (verified against the renderer): `RenderObserverBox.current`
is set to the client for the **entire render pass** and nil'd in a `defer`. It
is *not* scoped per component body. In production (`Renderer.swift:132`), the
box is set *before* `diff(...)`, so mount wiring (`wireStateAndRestore` →
`bind`, from `Diff.swift:243`) runs while `RenderObserverBox.current` is the
installed `QueryClient`.

**`TestRenderer` ordering (required, B1).** The test renderer wires the **root**
component out-of-band: `TestRenderer.init` calls `wireState(on: root, …)` at
`TestRenderer.swift:41` but doesn't set `RenderObserverBox.current` until
`:46` — so the root's `bind` would capture a `nil` client. `AsyncTestHarness`
always mounts the component-under-test *as the root*, so this is exactly the
path the §12 B1 test exercises. Fix: move the `RenderObserverBox.current =
queryClient` assignment **above** the root `wireState` call in
`TestRenderer.init` (mirroring production order). Listed in §2.

So `@Component`'s emitted `bind` wires each mutation runtime once, at mount
(§4, *What the macros emit*):

```swift
_create_mutationRuntime.wire(owner: owner, scheduler: scheduler,
                             client: _currentRenderQueryClient())  // public accessor over the package box
```

This makes mutations **correct by construction** — the client is present the
instant the component mounts, whether or not `body` ever reads `$create`. There
is no "reference the handle in `body` first" constraint and no silent-degrade
path. (An earlier rev captured the client lazily during `body`; the review
(B1) showed that lets a component whose `body` never touches `$create` run its
first `mutate` unwired — a silent data-correctness bug. Mount wiring removes the
failure mode entirely.)

If the client is somehow nil at wire time (e.g. a hand-rolled `Component` that
isn't mounted through the diff, or a unit test driving the runtime directly),
`beginOptimistic` fires an `assertionFailure` in DEBUG (loud, fail-fast at the
call site) and degrades in release: the write still runs in `finish`, only
optimism + invalidation are skipped — never a silently-wrong write.

### 8.3 Mutation task registration (for tests + settle)

`AsyncTestHarness.settle()` awaits `renderer.queryClient.inFlightTasks()`. Query
fetches are derived from `entries` (`QueryClient.swift:124`); mutations have no
entry, so the client gains a **separate, token-keyed** registry of in-flight
mutation tasks:

```swift
// QueryClient (package surface)
private var mutationTasks: [Int: Task<Void, Never>] = [:]   // token → task
private var nextMutationToken = 0

package func registerMutationTask(_ task: Task<Void, Never>) -> Int  // returns token
package func removeMutationTask(_ token: Int)                        // remove by token, NOT index
package func inFlightTasks() -> [Task<Void, Never>]                  // entries' inFlight + mutationTasks.values
```

The registered `Task<Void, Never>` removes itself by **token** in a `defer`
(`defer { client.removeMutationTask(token) }`) — not by array index, which
would race a concurrent removal that shifts indices. All access is `@MainActor`,
so the dictionary needs no further synchronization. (The `register(...)` calls
in §5.1 wrap this register-and-defer-remove pair.)

---

## 9. Error handling

- `perform` throwing → optimistic rollback (§6) → `status = .error`, `error` set, `isPending` false. The error surfaces through the handle for display.
- **No auto-retry** (consistent with Query Core). Retry = call `mutate` again.
- `mutateAsync` rethrows so call-site `do/catch` works; the handle's `error` is also populated, so fire-and-forget callers that don't catch still get a displayable error.
- `reset()` returns the handle to `.idle` and clears `data`/`error` (e.g. after the user dismisses an error).

---

## 10. Concurrency, re-entrancy & cancellation

- All mutation code is `@MainActor`; `perform` is the only suspension point.
- **Re-entrancy:** a second `mutate` while one is pending is **allowed**; both run, and `status`/`data`/`error` reflect the last to resolve. Each call captures its own independent rollback stack (local to its `run` invocation, §5.1), restored on that call's own failure. v1 does **not** queue or cancel concurrent mutations — UIs gate re-entry with `.disabled($create.isPending)`, the documented pattern. (Queue/cancel deferred, §14.)
- **Concurrent optimistic edits to the same key are NOT serializable in v1.** If two in-flight mutations both `.update` the same cache entry, mutation A's rollback restores the value it snapshotted, which may already have been overwritten by mutation B — classic optimistic-interleaving. The `isPending` gate makes this rare, but it is advisory, not enforced. Explicit known limitation.
- **Cancellation contract (the unmount/reset question, B2):**
  - **`reset()` does NOT cancel** an in-flight task. It returns the *published* state to `.idle`; an outstanding `perform` still completes and applies its success/failure transition + invalidation/rollback as normal. (Rationale: a write already sent to the server should still reconcile the cache; `reset` only clears the UI-facing state.)
  - **Unmount does NOT cancel** in v1. A `perform` that resolves after its component unmounts still runs its completion. This is safe because: `markDirty` on a dead `weak` owner no-ops; and the cache writes (invalidation refetch / optimistic rollback) act on the shared `QueryClient`, which outlives the component — the correct target, since other mounted observers of that key should still see the reconciled result. The runtime holds `owner` `weak`, so it does not retain the component.
  - Task-level cancellation (cooperative, via the surrounding `Task`) remains available to `perform` implementations but is not driven by `reset`/unmount in v1.

---

## 11. Required Query Core extension (package-internal)

```swift
// QueryClient+Cache.swift — NOT public in v1
extension QueryClient {
    /// Current cached value at `key`, typed, or nil if absent / type mismatch.
    package func getQueryData<V>(_ key: QueryKey, as type: V.Type) -> V?

    /// Type-erased read used by the optimistic engine (it holds Any? snapshots).
    package func getQueryDataErased(_ key: QueryKey) -> Any?

    /// Write `value` into the entry at `key`, notify observers, and protect the
    /// write from a concurrent in-flight fetch. See the generation contract below.
    package func setQueryData(_ key: QueryKey, _ value: Any?)
}
```

**The generation contract (B3).** The shipped cache has a per-entry generation
guard: `commitFetch` (`QueryClient.swift:94-118`) drops a fetch result unless
`entry.generation` still matches the value captured when the fetch was spawned,
and `forceStaleAndRefetch` (`:155-163`) bumps `generation` + cancels
`entry.inFlight`. Without coordination, an optimistic `setQueryData` racing an
in-flight SWR revalidation would be silently clobbered when that fetch resolves
via `commitFetch`. So `setQueryData` must, in one step:

1. `entry.inFlight?.cancel()` and bump `entry.generation` — so any fetch already
   in flight for this key is superseded and its `commitFetch` is dropped by the
   guard (the same mechanism `forceStaleAndRefetch` relies on).
2. Set `entry.value = value` and **leave the entry stale** (`lastFetched = nil`)
   so a later `invalidate(...)` still refetches — the optimistic value is
   provisional, not authoritative.
3. Run the existing `notify` path (prune-on-nil-owner semantics unchanged) so
   mounted `query()` observers re-render with the new value immediately.

This is the declarative equivalent of TanStack's "cancel outgoing refetches in
`onMutate` before applying optimistic data."

**Type-erasure contract.** `entry.value` is `Any?`, but the entry's
`valuesEqual` witness (`QueryEntry.swift`) was captured from the original
query's concrete `Q.Value`. The `Any` written by `setQueryData` **must** be that
same concrete type. v1 satisfies this by construction — `.update`'s transform is
`(Q.Value) -> Q.Value` — but the contract must be stated so future
`select`/change-detection work doesn't break silently.

**Absent entry.** `setQueryData` on a key with **no** entry is a no-op in v1
(optimistic edits target on-screen queries, which have live entries; `.update`
already returns `nil` and the engine logs in DEBUG, §6). Seeding absent entries
is deferred (§14).

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
- **B1 mount wiring:** a component that mounts a `@MutationState` but whose `body` **never references `$create`** still wires the client — its **first `mutate`, with no prior re-render**, applies optimism + invalidation (assert the optimistic value appears / a fetch counter bumps). The "no prior re-render" condition is load-bearing: it must fire `mutate` straight after `AsyncTestHarness.init` with no intervening `flush()`/`rerender`, so the test cannot pass for the wrong reason via a `rerender` that incidentally re-installs `RenderObserverBox.current` (`TestRenderer.swift:71`). This is the regression test for both the silent-degrade footgun and the `TestRenderer` ordering fix (§2/§8.2).
- **B3 generation guard:** with a background revalidation in flight for a key (gate it with a `Gate`, as in `supersedingFetchSurvivesStaleCompletion`), an optimistic `setQueryData` survives — when the superseded fetch later resolves, `commitFetch` is dropped by the guard and the optimistic value is *not* clobbered.
- **Cancellation:** `reset()` while a `perform` is in flight returns published state to `.idle`, but the still-running `perform` completes and applies its invalidation/rollback (assert via a fetch counter / cache value after `settle()`).

Macro:
- a golden expansion test for `@MutationState` (emitted `_*_mutationRuntime` + `$name` projection), paralleling existing `@State`/`@Component` macro tests.
- a golden expansion test for `@Component`'s extended `bind` — a class **with** a `@MutationState` emits the `_*_mutationRuntime.wire(...)` line; a class **without** one emits a `bind` byte-identical to today's (the conditional-emission guarantee, §2).

---

## 13. Required changes summary

**New (`SwiflowQuery`):** `Mutation.swift`, `Invalidation.swift`,
`OptimisticEdit.swift`, `MutationState.swift`, `MutationMacro.swift`,
`QueryClient+Cache.swift`.

**Modified:**
- `SwiflowQuery/QueryClient.swift` — token-keyed mutation-task registry surfaced through `inFlightTasks()`; `setQueryData` cancel+generation-bump (§11).
- `SwiflowMacrosPlugin/` — add `MutationStateMacro.swift`; **extend `ComponentMacro.swift`** to scan `@MutationState` and emit mount-time `wire(...)` into `bind` (B1); register `MutationStateMacro` in `SwiflowMacrosPlugin.swift`.
- `SwiflowTesting/TestRenderer.swift` — **ordering fix (B1):** install `RenderObserverBox.current` before the root `wireState` so mount-time mutation wiring on the root captures the client (§2/§8.2).
- `Package.swift` — add `"SwiflowMacrosPlugin"` to the `SwiflowQuery` target deps; confirm `SwiflowQuery`'s language mode (§2).

**No `Swiflow` *core/Diff* source changes.** The `RenderObserver` hook, the
`@Component`-emitted `runtimeOwner`/`runtimeScheduler`, and
`bind`/`wireStateAndRestore` are reused as-is. The two non-core changes are: the
`@Component` **macro** learning to scan `@MutationState` (its emitted
`QueryClient`/`RenderObserverBox` references are conditional on the component
declaring a mutation, so mutation-free code is byte-for-byte unaffected, §2),
and the one-line `TestRenderer` ordering fix above.

---

## 14. Non-goals / deferred

- Mutation-result cache / dedup / mutation history.
- Retries / backoff.
- Lifecycle callbacks on the `Mutation` type.
- Public `getQueryData`/`setQueryData` imperative cache surgery (the escape hatch for cross-query optimistic edits, §6).
- Concurrent-mutation queueing / cancellation, and serializable same-key optimistic edits (§10).
- `reset()`/unmount cancelling an in-flight `perform` (§10 — the v1 contract is *no* cancel).
- Optimistic `.set` and insert/remove helpers beyond `.update`.
- Seeding cache entries that have no live observer from `setQueryData`.

> Mount-time client wiring (formerly deferred here) was **pulled into v1** per the review (B1, §8.2) — a data layer must not silently drop a write's cache effects.

---

## 15. Design rationale — key forks and why

1. **Self-describing `Mutation` type (not closure-at-call-site).** Same identity as `Query`: deps + behavior + declared effects in one reusable, unit-testable value. The invalidation declaration is `(input, output) -> [Invalidation]` (not a static list) specifically so writes can target the server-assigned id.
2. **`@MutationState` + `$`-projection (not a `query()`-style body method).** Mutation state is local and imperative, the opposite of a query's shared declarative cache. Routing it through a `mutation()` body method would force **call-site positional identity** to fake per-component state — a brand-new fragility class the codebase doesn't have. `@MutationState` says exactly what it is: local reactive state, sibling to `@State`, with stable per-instance identity for free.
3. **Declarative `optimistic()` with engine-owned rollback (not imperative `onMutate`/`onError` hooks).** Turns the most error-prone part of mutations into a typed, declarative statement built on the existing typed `Query`. The imperative escape hatch (public `setQueryData`) stays deferred until a real case needs surgery the declarative form can't express.
4. **`mutate` / `mutateAsync` pair; side effects at the call site (not lifecycle callbacks).** Structured concurrency reads top-to-bottom where the action fires, and avoids re-introducing the callback model that declarative optimism just removed.
5. **Macro path forced by Swift constraints, landing parallel to `@State`.** Dependencies-in-`init` ⇒ `create` is the stored `Mutation`; one-type-per-property ⇒ the handle is the `$`-projection. The result is *more* consistent with `@State`. It needs no `Swiflow` *core/Diff* changes; the core-adjacent costs are the `@Component` macro scanning `@MutationState` to wire the client at mount (B1) and a one-line `TestRenderer` ordering fix — both accepted in exchange for correct-by-construction wiring with no silent-degrade path.
