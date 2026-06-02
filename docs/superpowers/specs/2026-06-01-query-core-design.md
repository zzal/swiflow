# Swiflow Query Core — Design Spec

**Date:** 2026-06-01
**Status:** Approved (brainstorm complete; hardened by swift-innovator-expert review) — ready for implementation plan
**Foundation:** Builds on Phase 20 async `.task` effects
(`docs/superpowers/specs/2026-06-01-phase20-async-tasks-design.md`).

> **Revision 2** folds in a stern design review. Material changes from the
> first draft: typed `QueryKeyComponent` enum (was `[AnyHashable]`);
> an explicit refetch **trigger model** so `.zero` staleTime does not storm;
> per-render subscription **reconciliation** (was subscribe-until-unmount with a
> lingering leak); a per-entry generation guard with pinned capture/compare
> points; a monotonic `Duration` clock; `QueryState` is no longer `Equatable`.
> The spec no longer claims `query()` reuses `.task`'s mechanism — it is a
> distinct component-level mechanism, argued on its own merits.
>
> **Revision 3** (during planning) replaces rev-2's "owner read off `self` via a
> macro-emitted `package` accessor" with a **diff-authoritative render-observer
> boundary hook** (§7.1/§7.2/§11). Per-render reconciliation needs a
> body-eval boundary signal in the diff regardless; since the diff already holds
> the authoritative `(owner, scheduler)` at that point, supplying it through the
> boundary hook makes the macro accessor redundant — **no macro change, no
> `ComponentMacroTests` snapshot churn**. The owner is *bound by the diff*, never
> *inferred by `query()`*, so the wrong-owner-near-`embed` risk the review raised
> still cannot occur. The user-facing API is unchanged.

---

## 1. Goal

A typed, shared, automatically-revalidating data-fetching layer for Swiflow —
the Swift+WASM analogue of TanStack Query / SWR — built on the Phase 20 async
foundation. One line in a component gets you cached, deduplicated,
stale-while-revalidate data with hierarchical and tag-based invalidation:

```swift
let user = query(UserByID(id: userID, api: api))   // QueryState<User>
```

This is **sub-project #1 of three**. Mutations and the background/lifecycle
layer are separate, later specs (see §12).

### What the Phase 20 foundation provides

`.task(rerunOn:)` already solves the hardest *per-component* problems —
lifecycle-bound async, cancellation, and stale-write dropping, re-running only
on key change. Query Core adds the parts that live **above** a single
component: a shared cache, request deduplication, stale-while-revalidate, and
cross-component invalidation. The re-render seam is `scheduler.markDirty(owner)`
— the same hook `@State` uses.

### In scope

- A typed, self-fetching `Query` protocol (identity + data type + fetch in one
  value).
- A shared `QueryClient` cache with per-key subscription → re-render.
- Request **deduplication** (concurrent identical keys share one in-flight
  fetch).
- **Stale-while-revalidate** with a single `staleTime` timer (default `.zero`)
  and an explicit refetch **trigger model** (§5).
- **Invalidation**: hierarchical key-prefix cascade **plus** cross-cutting
  tags. Both stateless functions of the current cache contents.
- `query(_:)` consumption as a `Component` method returning `QueryState<Value>`.
- Environment-injected client + injected monotonic clock for deterministic
  testing.

### Out of scope (explicitly deferred)

- Mutations, optimistic updates, auto-invalidation-on-mutation.
- Background refetch (window-focus, reconnect, polling interval).
- Garbage collection / eviction of unused entries; persistence.
- `select` (cached-value → derived-return-value transform).
- Automatic retry/backoff on failed fetches.
- Object/struct key components and object **subset** matching (v1 keys are
  string/int paths; see §3.1, §6).

---

## 2. Module & dependencies

A new module **`SwiflowQuery`**, a peer to `SwiflowRouter`, depending on the
`Swiflow` core module. `Package.swift` gains a `SwiflowQuery` target and a
`SwiflowQueryTests` test target. Cross-module access to core internals uses
`package` visibility (the established pattern — `SwiflowQuery` is in the same
Swift package, so `package` declarations in `Swiflow` are visible to it).

---

## 3. Core types

### 3.1 `QueryKey` — a typed hierarchical path

```swift
public enum QueryKeyComponent: Hashable, Sendable {
    case string(String)
    case int(Int)
}
extension QueryKeyComponent: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension QueryKeyComponent: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

public typealias QueryKey = [QueryKeyComponent]
public typealias QueryTag = String
```

A closed, `Sendable`, `Hashable` enum rather than `[AnyHashable]`. This fixes
three problems `[AnyHashable]` carries: it is a **Sendable hole** (`AnyHashable`
is not `Sendable`); it is a **type-confusion footgun** (`1` `Int` vs `Int64`
vs `"1"` silently fail to match); and it is **opaque in a debugger**. The enum
keeps the cascade (it is still an ordered, prefix-matchable, `Hashable` array
usable directly as a dictionary key) and stays ergonomic via literal
conformances:

```swift
let k: QueryKey = ["users", 1]        // literals: string + int
var queryKey: QueryKey { ["users", .int(id)] }   // a variable Int needs `.int(id)`
```

Non-`String`/`Int` identity (bools, enums, structs) is encoded into a `.string`
or `.int` component by the query (`["sort", .string(order.rawValue)]`).
Arbitrary struct ("object") components and object-subset matching are deferred
(§6, §12).

### 3.2 `Query` — the key *is* the query

```swift
public protocol Query {
    associatedtype Value: Equatable & Sendable

    /// Hierarchical identity. Determines cache slot and prefix-cascade matching.
    /// Excludes captured dependencies (§3.5).
    var queryKey: QueryKey { get }

    /// Cross-cutting invalidation families. Stateless — computed by the query
    /// about itself. Defaults to empty.
    var tags: Set<QueryTag> { get }

    /// Freshness window measured from the last successful fetch. Defaults to
    /// `.zero` (a *trigger* always revalidates; see §5 — this does NOT mean
    /// every render refetches).
    var staleTime: Duration { get }

    /// Fetch the value. Run by the client inside a `@MainActor` Task, so
    /// captured deps and `Value` never cross an isolation boundary (the WASM
    /// runtime is single-threaded anyway). Cancellation is cooperative via the
    /// surrounding Task — no explicit signal parameter.
    func fetch() async throws -> Value
}

public extension Query {
    var tags: Set<QueryTag> { [] }
    var staleTime: Duration { .zero }
}
```

`Query` is intentionally **not** `Sendable`: it may capture a non-`Sendable`
dependency (e.g. a class-based API client). Because the client both stores and
invokes the query on the `@MainActor`, nothing is sent across actors, so
`Sendable` would be a needless constraint on app dependencies. Only `Value` is
`Sendable` (it may return across the `await` in `fetch`).

### 3.3 `QueryState<Value>` — what the component sees

A **struct**, not an enum, because stale-while-revalidate has two orthogonal
axes an enum cannot hold simultaneously — *do we have data* and *is a fetch in
flight right now*:

```swift
public struct QueryState<Value> {
    /// Last successful value. RETAINED across refetch — this is what makes SWR
    /// work (show old data while revalidating).
    public var data: Value?

    /// Last fetch error, if the most recent fetch failed. Read-only data the
    /// component may display.
    public var error: (any Error)?

    /// True iff there is no data yet AND a fetch is in flight (first load).
    public var isLoading: Bool

    /// True iff a fetch is in flight, including background revalidation of
    /// already-present data.
    public var isFetching: Bool

    public var isSuccess: Bool { data != nil }
}
```

`QueryState` is **not** `Equatable` — it is never on the re-render path
(`query()` returns a fresh value each render; re-render is driven by the client
calling `markDirty`, not by comparing `QueryState`s). Dropping the conformance
removes both the need to compare `data` (handled elsewhere; see below) and the
problem of comparing a non-`Equatable` `any Error`.

The **change-detection** witness (`Query.Value: Equatable`, carried into the
cache as a type-erased closure) is **reserved infrastructure for a future
`select` optimization, not a v1 markDirty gate.** In v1 the client notifies
subscribers on every fetch *start* and *completion* — this is required so
`isFetching` toggles and the SWR indicator clears on completion *regardless* of
whether `data` changed (gating the completion notify on value-equality would
leave a stuck spinner). Identical-output re-renders are absorbed by the VNode
diff (zero patches), exactly as the spec defers `select` (§13). So `Value:
Equatable` is held for when `select` lands; it does not suppress re-renders in
v1.

### 3.4 `QueryClient` and the clock

```swift
public protocol QueryClock {   // not Sendable — read on the @MainActor only
    /// Monotonic time elapsed since an arbitrary fixed origin. Monotonic so a
    /// wall-clock adjustment can never make a fresh entry look stale.
    func now() -> Duration
}

@MainActor
public final class QueryClient {
    public init(clock: any QueryClock = SystemQueryClock())

    /// Hierarchical cascade. Marks every entry whose key STARTS WITH `key`
    /// (or equals it exactly when `exact: true`) as stale, and refetches the
    /// currently-mounted ones immediately. Unmounted matches refetch on next
    /// mount.
    public func invalidate(_ key: QueryKey, exact: Bool = false)

    /// Cross-cutting cascade — matching entries whose `tags` contain `tag`.
    public func invalidate(tag: QueryTag)

    // Internal (detailed in the plan):
    //   entries[QueryKey] -> Entry { value, error, lastFetched: Duration,
    //                                inFlight: Task?, generation: Int,
    //                                lastQuery: any Query, tags, equals: (Any,Any)->Bool }
    //   subscribers[QueryKey] -> set of weak (owner: AnyComponent, scheduler: Scheduler)
    //   observed[ObjectIdentifier(owner)] -> Set<QueryKey>   // for per-render reconciliation
}
```

`SystemQueryClock` uses **`performance.now()`** in the browser (monotonic,
millisecond resolution, immune to wall-clock jumps), converted to `Duration`,
and a monotonic host clock under host-Swift tests. Tests inject a `ManualClock`
they advance explicitly (§10). Freshness is `now() - entry.lastFetched`
compared against `staleTime`, all `Duration` arithmetic; `.zero` makes the
comparison always-stale (but see §5 — staleness only matters at a *trigger*).

### 3.5 Dependencies as non-identity key properties

`fetch()` runs *after* render commit, so it cannot read `@Environment`
(`AmbientEnvironment.current` is set only during `body`). Dependencies are
therefore ordinary **stored properties on the key, excluded from `queryKey`**,
injected at the component boundary and defaulted for clean app call sites:

```swift
struct UserByID: Query {
    let id: Int
    let api: API                                  // dependency — NOT in queryKey
    var queryKey: QueryKey { ["users", .int(id)] }
    func fetch() async throws -> User { try await api.get("/users/\(id)") }

    init(id: Int, api: API = .live) { self.id = id; self.api = api }
}
```

A key is three things: **identity** (`queryKey`), **behavior** (`fetch`), and
**captured deps** (stored properties excluded from identity). Caching and dedup
key off `queryKey` only, so a real vs fake `api` never changes the cache slot.
Tests inject a fake `api` at the component's `init` — the Phase 20
`fetch:`-injection pattern, one level out.

**Contract (same as TanStack):** equal `queryKey`s must denote equivalent
fetches. Do not reuse a key for genuinely different fetchers.

---

## 4. Consumption — Shape B

`query(_:)` is a `Component` extension method in `SwiflowQuery`:

```swift
public extension Component {
    func query<Q: Query>(_ q: Q) -> QueryState<Q.Value>
}
```

```swift
@MainActor @Component
final class Profile {
    @State var userID: Int
    let api: API
    init(userID: Int, api: API = .live) { self.userID = userID; self.api = api }

    var body: VNode {
        let user = query(UserByID(id: userID, api: api))   // dynamic key, zero ceremony
        return div {
            if let u = user.data { p(u.name) }
            else if user.isLoading { p("Loading…") }
            if let e = user.error { p("Error: \(e.localizedDescription)", .class("error")) }
            if user.isFetching { span("⟳") }                // SWR background-refresh hint
        }
    }
}
```

`query()` reads the owner+scheduler off `self` (§7.1), reads the injected
client from `@Environment(\.queryClient)` (valid because it is called during
`body`), returns the current cached snapshot, and records that this component
observed this key this render (§7.2). It performs **no** fetch or subscription
mutation during `body`; those happen at post-commit reconciliation.

**Why a method, not a `@Query` property wrapper:** dynamic keys come for free
(the key is computed inline from live `@State` — where SwiftData's `@Query`
macro gets awkward); subscriptions key off the query key, not call order, so
there is no React-style "rules of hooks" ordering constraint; and it needs no
new macro.

---

## 5. Data flow, freshness & the refetch trigger model

### Reading (during `body`, pure)

`query(key)` returns the current snapshot synchronously:

- **Absent** → `isLoading = true`, no `data`.
- **Present** → carries `data`; `isFetching = true` iff a fetch is currently in
  flight for that key.

It also records `(owner, key)` in this render's observation set. No side effects.

### Refetch triggers (at post-commit reconciliation — NOT every render)

A re-render is **not** a refetch trigger. This is the crucial correction that
keeps `.zero` staleTime from storming: `query()` runs on every `body` eval, but
a fetch is started only on an actual trigger, each gated by staleness:

1. **A component observes a key it was not observing in the previous render** —
   i.e. mount, or the key changed (the `[old keys] → [new keys]` set diff from
   §7.2). Gated by staleness: a *fresh* present entry serves without network; an
   *absent* or *stale* entry fetches (stale → SWR: serve old `data` +
   `isFetching`, fetch in background).
2. **`invalidate(...)`** — forces matching entries stale and refetches the
   currently-mounted subscribers now.

A component re-observing the **same** key across consecutive renders is **not** a
trigger and never fetches, even though `.zero` marks it stale. `staleTime` only
decides whether a *triggered* observation revalidates (fresh) or serves cached
data (stale → revalidate). With `.zero`, every trigger revalidates; plain
re-renders still do not. This mirrors TanStack's real semantics (triggers =
mount, key-change, invalidate, focus/reconnect) and the `.task(rerunOn:)`
foundation (re-run on key change only).

### Deduplication

At most one in-flight `Task` per key. A trigger for a key already fetching
attaches to the existing `Task` instead of starting another.

### Completion

When a fetch resolves, the client passes the generation guard (§7.4), writes
the result into the entry, and — only if the new `Value` differs from the old
(§3.3) — calls `scheduler.markDirty(owner)` for each live subscriber → normal
re-render → `body` re-reads the fresh snapshot.

---

## 6. Invalidation

```swift
client.invalidate(["users"])                    // cascade → UserByID(any), UserPosts(any), …
client.invalidate(["users", 1])                 // → UserByID(1), UserPosts(userID: 1)
client.invalidate(["users", 1], exact: true)    // → ONLY UserByID(1)
client.invalidate(tag: "team:3")                // cross-cutting family
```

**Prefix match (positional cascade):** an entry matches `invalidate(prefix)` iff
its key starts with `prefix` — `Array(entryKey.prefix(prefix.count)) == prefix`.
`exact: true` requires full equality. (Trivial and total over the typed
components.)

**Tag match (cross-cutting cascade):** an entry matches `invalidate(tag:)` iff
its `tags` set contains `tag`. Tags are computed by each query about itself
(stateless, like the key) — capturing relational families (e.g. every `user`
on `team 3`) without a maintained parent-child edge graph.

**Effect of a match:** force the entry stale; currently-mounted subscribers
refetch immediately (background fetch + change-gated `markDirty`); unmounted
matches refetch on next mount. Both matchers are pure functions of the present
cache contents — they never reach entries the client does not currently hold.

Object/struct key components and TanStack's object-subset matching are deferred
(v1 components are `.string`/`.int`, matched by equality; the hierarchy lives in
the array levels, which prefix-matching fully covers).

---

## 7. Lifecycle & re-render wiring

This section defines the contract with the `Swiflow` core. The required core
changes are in §11.

### 7.1 Owner identity from the diff (render-observer boundary)

The core gains one general, query-agnostic seam: a `package` **render-observer
boundary hook**. `Swiflow` declares a `package protocol RenderObserver` with
`willEvaluate(owner:scheduler:)`, `didEvaluate()`, and
`componentDidUnmount(_:)`, plus a `package` ambient `currentRenderObserver:
(any RenderObserver)?`. The diff fires `willEvaluate`/`didEvaluate` around each
component's `body` evaluation, at the existing `AmbientEnvironment.current`
bracket sites (so it nests correctly through `embed { Child() }`), and
`componentDidUnmount` from the destroy path. `SwiflowQuery` installs an observer
(the `QueryClient` itself conforms); the renderer save/restores
`currentRenderObserver` around its render, exactly as it already does for
`SwiflowTaskRuntime.currentScope`.

`query()` therefore attributes its observed keys to the owner **the diff
supplied** at the active boundary — it never *infers* the owner. This is an
ambient current-owner, but a safe one: the binding is authoritative (the diff
knows precisely which component's `body` it is evaluating) and rides the same
bracket `AmbientEnvironment` uses, so the wrong-owner-near-`embed` failure mode
cannot arise. It needs **no macro change** and no `_ComponentRuntime` accessor —
the diff already holds `(AnyComponent, Scheduler)` at the eval site.

### 7.2 Collect-during-body, reconcile-at-boundary (a distinct mechanism)

This is **not** how `.task` works — `.task` closures are attached to element
`VNode`s and slot-reconciled by the diff (`DiffTasks.swift`). Queries are a
*component-level* concern, so they use a different mechanism, driven by the
render-observer boundary (§7.1):

- `willEvaluate(owner:scheduler:)` opens a fresh observation frame for the
  component about to render.
- During `body`, each `query(key)` call records `key` (plus a type-erased fetch
  and `Equatable` witness) into that frame and returns the current snapshot — a
  pure read otherwise (no fetch spawned, no subscription mutated during `body`).
- `didEvaluate()` hands the completed frame to the client, which **reconciles**
  it against that component's previous observation set:
  - **new keys** (observed now, not before) → subscribe + apply the §5 trigger
    (fetch if absent/stale);
  - **dropped keys** (observed before, not now) → unsubscribe;
  - **retained keys** → no-op (no trigger).

This single per-render diff drives both the trigger model (§5) and subscription
cleanup (§7.3) — one mechanism, no leak.

### 7.3 No lingering subscriptions

Because §7.2 unsubscribes dropped keys every render, a component that cycles
through keys (`userID` 1→2→…→N) holds only its *current* subscriptions — not an
unbounded, never-swept accumulation. (The earlier "benign lingering
subscription" idea was a real leak given GC is deferred; per-render
reconciliation replaces it.) On unmount, the diff's destroy path notifies the
client to drop the component's remaining subscriptions and observation record
(§11).

### 7.4 Per-entry generation guard (stale-result dropping)

Each cache `Entry` holds a monotonically-increasing `generation`. A fetch
**captures** the entry's generation when it is spawned. When it resolves — back
on the `@MainActor`, *after* the `await` returns and *before* committing — it
**compares** the captured generation against the entry's current one and commits
only if they match. A supersede (a newer trigger) or an `invalidate` bumps the
generation, so a stale or cancelled fetch's result is dropped before it can
touch the entry. Cancellation is additionally cooperative: the client cancels
the in-flight `Task`, unwinding `fetch()`'s `await`s.

This is a **separate, per-entry counter owned by the client** — *not* a reuse of
`SwiflowTaskRuntime.liveGenerations`, which is keyed by `.task` `slotID` and
belongs to a different concern. It is the same *idea* as Phase 20's write-guard
(drop superseded work in the bedrock, not at the call site), implemented where
it belongs. There is no data race (all on `@MainActor`); the guard closes the
*logical* race at the `await` suspension point.

### 7.5 Concurrency

`QueryClient`, components, scheduler, and diff are all `@MainActor`. The client
spawns each fetch as a `@MainActor` `Task` capturing the (non-`Sendable`) query
value from `@MainActor` context — no actor crossing, so deps need not be
`Sendable`. The `await`ed network work suspends (the WASM runtime is
single-threaded; suspension does not block); `Value: Sendable` covers the value
returning across the suspension.

---

## 8. Client injection & manual refetch

### 8.1 Per-root client (installed as the render observer)

Each render root owns one `QueryClient`. The renderer installs it as the active
`RenderObserver` (§11 item 2), save/restored around the render — so during a
given root's render that root's client is the active observer, and `query()`
obtains it from there (`currentRenderObserver as? QueryClient`). A default client
is created at the render root; tests inject their own (with a `ManualClock`). No
separate `\.queryClient` environment key is required, and no global singleton —
per-root, save/restored, nothing process-global to pollute across tests/roots
(the Phase 20 isolation lesson).

### 8.2 Manual refetch

There is no `refetch` closure on `QueryState`. To refresh imperatively (e.g. a
"Refresh" button), the component **captures the client during `body`** (the
standard "capture during body" pattern, since event handlers run outside the
render cycle) and calls `client.invalidate(key)` from the handler.

---

## 9. Error handling

A failed `fetch()` sets `QueryState.error` and **leaves any prior `data` in
place** (a failed revalidation does not erase good data). There is **no
automatic retry in v1**; the app retries via `invalidate`/refetch. Retry/backoff
belongs with the background/resilience layer (§12). `error` is `(any Error)?`,
surfaced as read-only data for the component to display.

---

## 10. Testing strategy

- **Cache + freshness:** construct `QueryClient(clock: ManualClock())` and
  advance the clock across `staleTime` boundaries deterministically — no
  sleeping.
- **Component integration:** `AsyncTestHarness` (Phase 20) with an injected
  `QueryClient`. `settle()` drives in-flight fetches and flushes re-renders to a
  fixed point; its `maxRounds` cap turns a pathological unstable-key loop (§13
  S5) into a clear test failure rather than a hang. Inject fake fetch behavior
  via the component's defaulted dep (`Profile(userID: 1, api: FakeAPI())`).
- **Trigger model:** assert that a plain re-render (same key) does **not**
  refetch, while a key change and an `invalidate` **do**.
- **Dedup:** N concurrent observations of one key produce one `fetch()` (a
  counting fake).
- **Invalidation:** prefix cascade, `exact` narrowing, and tag matching each
  refetch the right mounted observers and leave non-matches untouched.
- **Generation guard:** a superseded slow fetch must not clobber a newer fast
  fetch's result.
- **Reconciliation:** a component that changes its key unsubscribes from the old
  key (asserted via subscriber count / no refetch on old-key invalidation).

`ManualClock` lives in the query test support (or `SwiflowTesting` — decided in
the plan).

---

## 11. Required core changes (`Swiflow`)

1. **A general `package` render-observer boundary hook.** Add to `Swiflow` core:
   a `package protocol RenderObserver` (`willEvaluate(owner:scheduler:)`,
   `didEvaluate()`, `componentDidUnmount(_:)`) and a `package` ambient
   `currentRenderObserver: (any RenderObserver)?` (an `enum` holding a
   `nonisolated(unsafe) static var`, mirroring `AmbientEnvironment`). The diff
   fires `willEvaluate`/`didEvaluate` around each component's `body` eval at the
   existing `AmbientEnvironment` bracket sites (`Diff.swift` ~253/256 and
   ~423/426), and `componentDidUnmount` from `destroy(...)` alongside the
   existing `cancelTasks(on:)` call. `TestRenderer` fires the same around its
   direct root-body evals (where it already sets `SwiflowTaskRuntime.currentScope`).
   Core stays query-agnostic; `SwiflowQuery` provides the observer that drives
   §7.2 reconciliation. **No macro change, no snapshot churn.**
2. **Renderer/TestRenderer install the observer.** Each render root creates (or
   is injected) a `QueryClient`, injects it via `@Environment(\.queryClient)`,
   and save/restores `Swiflow.currentRenderObserver = client` around its render —
   the identical pattern already used for `SwiflowTaskRuntime.currentScope`.

(Rev-1's "ambient current-component" and rev-2's "macro accessor" are both
superseded by this single query-agnostic boundary hook — §7.1.)

---

## 12. Deferred sub-projects (separate specs)

- **#2 Mutations** — a `Mutation` analogue, optimistic updates with rollback,
  auto-invalidation of affected query keys/tags on success.
- **#3 Background & lifecycle** — refetch on window-focus / reconnect /
  polling interval; GC of unused entries; optional persistence.
- **Refinements** — `select` (with subscriber-level change-detection for the
  expensive-`body` case); object/struct key components + object-subset matching;
  auto-retry/backoff; variadic `query()` dependency composition.

---

## 13. Design rationale — key forks and why

- **Self-fetching typed key** (over call-site fetcher / client-registered
  fetcher): one fully-typed value carries identity + data type + fetch; the
  client can refetch/dedup/invalidate any key it holds. Deps-as-non-identity
  props preserve testability without splitting the definition across a
  registration step.
- **Typed `QueryKeyComponent` enum** (over `[AnyHashable]`): `Sendable`,
  type-safe (`Int` vs `Int64` vs `String` can't silently miss), debuggable, and
  still prefix-cascadable, with literal ergonomics. Arbitrary-struct components
  deferred — and they were the only thing `[AnyHashable]` bought.
- **`[component]` prefix cascade + tags** (over a relational parent-child edge
  graph): the cascade gives TanStack's headline ergonomic; tags give relational
  ("everything on team 3") cascade *statelessly*. A maintained edge graph was
  rejected — a query cache holds only a transient, partial working set, so a
  graph pays cycle-detection + edge-lifecycle costs to reach exactly the same
  "currently-known entries" a stateless matcher already reaches.
- **`staleTime` default `.zero` + an explicit trigger model** (over treating
  every render as a refetch): correct-by-default freshness *without* a refetch
  storm — triggers are mount/key-change/invalidate, gated by staleness; plain
  re-renders never fetch.
- **Owner from the diff via a render-observer boundary** (over a `query()`-read
  ambient, and over a macro-emitted off-`self` accessor): per-render
  reconciliation needs a body-eval boundary signal in the diff regardless, and
  the diff already holds the authoritative `(owner, scheduler)` there — so the
  boundary hook supplies it, the owner is *bound* not *inferred* (no
  wrong-owner-near-`embed` bug), and there is no macro change or snapshot churn.
  A strictly cleaner seam than rev-1's ambient or rev-2's accessor.
- **Per-render subscription reconciliation** (over subscribe-until-unmount):
  with GC deferred, the lingering-subscription approach was an unbounded leak;
  the per-render set-diff also *is* the trigger mechanism, so it costs little.
- **Per-entry generation guard owned by the client** (over reusing
  `SwiflowTaskRuntime.liveGenerations`): the task registry is slot-keyed and
  belongs to `.task`; the cache needs its own per-entry counter, with capture at
  spawn and compare-before-commit pinned.
- **Shape B `query()` method returning a non-`Equatable` struct** (over a
  `@Query` property wrapper; over an `Equatable` struct): free dynamic keys, no
  rules-of-hooks ordering, no new macro; `QueryState` is never on the re-render
  path so it needs no `Equatable` (which also dodges comparing `any Error`).
  Change-detection lives in the client via `Value: Equatable`.
- **`select` deferred**: in Shape B you transform inline, and Swiflow's VNode
  diff already absorbs the no-op re-renders React needs `select` to prevent. The
  only genuine win (skipping an expensive `body`) needs subscriber-memoization
  machinery — out of scope for v1.
```
