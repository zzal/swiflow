# Swiflow Query Core — Design Spec

**Date:** 2026-06-01
**Status:** Approved (brainstorm complete) — ready for implementation plan
**Foundation:** Builds directly on Phase 20 async `.task` effects
(`docs/superpowers/specs/2026-06-01-phase20-async-tasks-design.md`).

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

### What the Phase 20 foundation already provides

`.task(rerunOn:)` already solves the hardest *per-component* problems —
lifecycle-bound async, cancellation, and stale-write dropping. Query Core adds
the parts that live **above** a single component: a shared cache, request
deduplication, stale-while-revalidate, and cross-component invalidation. The
architectural seam is `scheduler.markDirty(owner)` — the same re-render hook
`@State` uses.

### In scope

- A typed, self-fetching `Query` protocol (identity + data type + fetch in one
  value).
- A shared `QueryClient` cache with per-key subscription → re-render.
- Request **deduplication** (concurrent identical keys share one in-flight
  fetch).
- **Stale-while-revalidate** with a single `staleTime` timer (default `.zero`).
- **Invalidation**: hierarchical key-prefix cascade **plus** cross-cutting
  tags. Both stateless functions of the current cache contents.
- `query(_:)` consumption as a `Component` method returning `QueryState<Value>`.
- Environment-injected client + injected clock for deterministic testing.

### Out of scope (explicitly deferred)

- Mutations, optimistic updates, auto-invalidation-on-mutation.
- Background refetch (window-focus, reconnect, polling interval).
- Garbage collection / eviction of unused entries; persistence
  (localStorage/IndexedDB).
- `select` (cached-value → derived-return-value transform).
- Automatic retry/backoff on failed fetches.
- Object **subset** matching inside a key component (object key components are
  matched by full equality; see §6).

---

## 2. Module & dependencies

A new module **`SwiflowQuery`**, a peer to `SwiflowRouter`, depending on the
`Swiflow` core module. Components import `SwiflowQuery` (or it is re-exported
from `SwiflowWeb`, decided in the plan) to get the `query(_:)` method and the
query types.

`Package.swift` gains a `SwiflowQuery` target and a corresponding test target
`SwiflowQueryTests`. Cross-module access to core internals uses `package`
visibility (the established pattern — `SwiflowQuery` is in the same Swift
package, so `package` declarations in `Swiflow` are visible to it).

---

## 3. Core types

### 3.1 `Query`

The key **is** the query: one value carries identity, data type, and how to
fetch.

```swift
public typealias QueryKey = [AnyHashable]   // hierarchical path; ["users"] is the 1-element case
public typealias QueryTag = String

public protocol Query: Sendable {
    associatedtype Value: Equatable & Sendable

    /// Hierarchical identity. Determines cache slot and prefix-cascade matching.
    /// Excludes captured dependencies (see §3.4).
    var queryKey: QueryKey { get }

    /// Cross-cutting invalidation families. Stateless — computed by the query
    /// about itself. Defaults to empty.
    var tags: Set<QueryTag> { get }

    /// Freshness window measured from the last successful fetch. Defaults to
    /// `.zero` (always background-revalidate on access).
    var staleTime: Duration { get }

    /// Fetch the value. Cancellation is cooperative via the surrounding Task
    /// (no explicit signal parameter — `URLSession` et al. honor Task
    /// cancellation natively). Captured deps are stored properties (§3.4).
    func fetch() async throws -> Value
}

public extension Query {
    var tags: Set<QueryTag> { [] }
    var staleTime: Duration { .zero }
}
```

`QueryKey = [AnyHashable]` is the Swift-native form of TanStack's `unknown[]`:
strings, ints, and any `Hashable` struct ("object" components) all drop in, and
the whole array is `Hashable`, so it is the cache map's key directly. A bare
`"users"` is simply `["users"]`.

### 3.2 `QueryState<Value>`

What the component sees. A **struct**, not an enum, because stale-while-
revalidate has two orthogonal axes an enum cannot hold simultaneously — *do we
have data* and *is a fetch in flight right now*:

```swift
public struct QueryState<Value: Equatable>: Equatable {
    /// Last successful value. RETAINED across refetch — this is what makes SWR
    /// work (show old data while revalidating).
    public var data: Value?

    /// Last fetch error, if the most recent fetch failed.
    public var error: (any Error)?

    /// True iff there is no data yet AND a fetch is in flight (first load).
    public var isLoading: Bool

    /// True iff a fetch is in flight, including background revalidation of
    /// already-present data.
    public var isFetching: Bool

    public var isSuccess: Bool { data != nil }

    // Equality is hand-written: compares `data`, `isLoading`, `isFetching`,
    // and the *presence + localizedDescription* of `error`. The raw `any Error`
    // is excluded from `==` (it is not Equatable) — the same technique
    // `ElementData ==` uses to skip non-Equatable fields.
    public static func == (lhs: Self, rhs: Self) -> Bool { /* see plan */ }
}
```

### 3.3 `QueryClient` and `QueryClock`

```swift
public protocol QueryClock: Sendable {
    /// Current time in seconds since an arbitrary fixed epoch. Monotonic
    /// enough for freshness comparison.
    func now() -> Double
}

@MainActor
public final class QueryClient {
    public init(clock: any QueryClock = SystemQueryClock())

    /// Hierarchical cascade. Marks every entry whose key STARTS WITH `key`
    /// (or equals it exactly when `exact: true`) as stale, and refetches the
    /// currently-mounted ones immediately. Unmounted matches refetch on next
    /// mount.
    public func invalidate(_ key: QueryKey, exact: Bool = false)

    /// Cross-cutting cascade. Same effect, matching entries whose `tags`
    /// contain `tag`.
    public func invalidate(tag: QueryTag)

    // Internal state (detailed in the plan):
    //   entries[QueryKey]      -> Entry  (value, error, lastFetched, inFlight Task, generation, last-seen Query value, tags)
    //   subscribers[QueryKey]  -> set of weak (owner: AnyComponent, scheduler: Scheduler)
}
```

`SystemQueryClock` reads JS time in the browser (`Date.now() / 1000`) and a
host clock under host-Swift tests. Tests inject a manual clock (§9).

### 3.4 Dependencies as non-identity key properties

`fetch()` runs *after* render commit (like `.task`), so it cannot read
`@Environment`. Dependencies are therefore ordinary **stored properties on the
key, excluded from `queryKey`**, injected at the component boundary and
defaulted for clean app call sites:

```swift
struct UserByID: Query {
    let id: Int
    let api: API                                  // dependency — NOT in queryKey
    var queryKey: QueryKey { ["users", id] }      // identity excludes `api`
    func fetch() async throws -> User { try await api.get("/users/\(id)") }

    init(id: Int, api: API = .live) { self.id = id; self.api = api }
}
```

A key is thus three things: **identity** (`queryKey`), **behavior** (`fetch`),
and **captured deps** (stored properties excluded from identity). Caching and
dedup key off `queryKey` only, so a real vs fake `api` never changes the cache
slot. Tests inject a fake `api` at the component's `init` — the Phase 20
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

**Why a method, not a `@Query` property wrapper:** dynamic keys come for free
(the key is computed inline from live `@State` — exactly where SwiftData's
`@Query` macro gets awkward); subscriptions key off the query key, not call
order, so there is no React-style "rules of hooks" ordering constraint; and it
reuses the component's existing runtime wiring rather than adding a new macro.

---

## 5. Data flow & freshness

On each `query(key)` call during `body`:

1. The client returns the **current snapshot** synchronously (a pure read).
2. **No entry** → snapshot is `isLoading = true`; a fetch is scheduled.
3. **Fresh entry** (`now − lastFetched < staleTime`) → snapshot carries `data`;
   no network.
4. **Stale entry** (default, since `staleTime == .zero` ⇒ always stale) →
   snapshot carries the existing `data` with `isFetching = true`; a background
   fetch is scheduled (**stale-while-revalidate**).

**Deduplication:** at most one in-flight `Task` per key. A second request for a
key already fetching attaches to the existing `Task` rather than starting a new
one.

When a scheduled fetch resolves, the client writes the result into the entry
and calls `scheduler.markDirty(owner)` for each live subscriber → normal
re-render → `body` re-reads the fresh snapshot.

`staleTime` is `Duration`; freshness compares `clock.now()` (seconds) against
the entry's `lastFetched`, converting `Duration` to seconds. `.zero` makes
every access stale ⇒ background revalidation on every mount/key-change, with
instant cached paint via SWR and at most one fetch via dedup.

---

## 6. Invalidation

```swift
client.invalidate(["users"])              // cascade → UserByID(any), UserPosts(any), …
client.invalidate(["users", 1])           // → UserByID(1), UserPosts(userID: 1)
client.invalidate(["users", 1], exact: true)  // → ONLY UserByID(1)
client.invalidate(tag: "team:3")          // cross-cutting family
```

**Prefix match (positional cascade):** an entry matches `invalidate(prefix)` iff
its key starts with `prefix` — `Array(entryKey.prefix(prefix.count)) == prefix`.
`exact: true` requires full equality.

**Tag match (cross-cutting cascade):** an entry matches `invalidate(tag:)` iff
its `tags` set contains `tag`. Tags are computed by each query about itself
(stateless, like the key) — capturing relational families (e.g. every `user`
on `team 3`) without a maintained parent-child edge graph.

**Effect of a match:** the entry is forced stale; currently-mounted subscribers
refetch immediately (background fetch + `markDirty`); unmounted matches refetch
on next mount. Both matchers are pure functions of the present cache contents —
they never reach entries the client does not currently hold.

**Object components matched by equality (v1):** a `Hashable` struct used as a
key component (e.g. a `Filter`) matches by full equality, not subset. TanStack's
object-subset matching (`{a:1}` ⊆ `{a:1,b:2}`) is deferred; in practice the
hierarchy lives in the array levels, which prefix-matching fully covers.

---

## 7. Lifecycle & re-render wiring

This section defines the contract with the `Swiflow` core. Three small core
changes are required (§11).

### 7.1 Ambient current component

The diff sets an **ambient current `(component, scheduler)`** around each
component's `body` evaluation — the same shape as `AmbientEnvironment.current`
and `TaskScope.currentScope`, at `package` visibility. `query()` reads this to
learn whom to subscribe and whom to `markDirty`.

### 7.2 Collect-during-body, act-after-commit

`query()` during `body` performs only a pure read of the current snapshot and
**records interest** (the key + the ambient owner/scheduler) into a per-render
scratch list. After the render commits, a post-commit hook hands the collected
interests to the client, which then **subscribes** the owner and **schedules any
needed fetch**. This is the same discipline `.task` uses (collect closures
during body, spawn after commit), keeping `body` side-effect-free.

### 7.3 Subscribe-on-use, unsubscribe-on-unmount

A component is subscribed to a key the first time it `query()`s it; it is
unsubscribed when it unmounts (the diff's destroy path notifies the client).

When a component's key changes (e.g. `userID` 1→2), the old key's subscription
**lingers harmlessly** until unmount — benign over-subscription (at most a
spurious re-render if the old key is later invalidated, which `body`'s re-read
absorbs). This avoids per-render subscription reconciliation entirely; the
deferred GC layer will sweep lingering subscriptions/entries.

### 7.4 Cache-level generation guard (stale-result dropping)

Each scheduled fetch carries a monotonically-increasing **generation** stamped
on its entry. When a fetch resolves, the client commits its result only if the
entry's live generation still matches; a fetch superseded by a newer fetch or
by an invalidation is dropped before it can touch the entry. Cancellation is
cooperative: the client cancels the in-flight `Task`, and `fetch()`'s `await`s
unwind. This is the cache-level echo of Phase 20's `@State` write-guard —
correctness in the bedrock, not at the call site. `fetch()` therefore needs no
`isCancelled` ceremony and no `signal` parameter.

### 7.5 Concurrency

`QueryClient`, components, scheduler, and diff are all `@MainActor`, matching
the rest of the runtime. The fetch `Task` is `@MainActor` (as Phase 20's
`TaskBody` is); `await`ed network work suspends off the main actor and results
are applied on it. `Value: Sendable` covers the suspension boundary.

---

## 8. Client injection & manual refetch

### 8.1 Environment-injected client

The client is read via `@Environment(\.queryClient)`. A default `QueryClient`
is created at the render root if none is injected; tests inject their own client
(with a manual clock). No global singleton — the Phase 20 isolation lesson
(per-root scope, nothing process-global to pollute across tests/roots).

Because `query()` is called during `body`, `AmbientEnvironment.current` is set,
so reading `\.queryClient` there is valid.

### 8.2 Manual refetch

There is no `refetch` closure on `QueryState` (that would break its clean
`Equatable`). To refresh imperatively (e.g. a "Refresh" button), the component
**captures the client during `body`** (the standard "capture during body"
pattern, since event handlers run outside the render cycle) and calls
`client.invalidate(key)` from the handler. `invalidate` forces the entry stale
and refetches the mounted observer.

---

## 9. Error handling

A failed `fetch()` sets `QueryState.error` (and leaves any prior `data` in
place — a failed revalidation does not erase good data). There is **no automatic
retry in v1**; the app retries via `invalidate`/refetch. Retry/backoff belongs
with the background/resilience layer.

`error` is `(any Error)?`; `QueryState`'s hand-written `==` compares error
presence and `localizedDescription`, not error identity.

---

## 10. Testing strategy

- **Cache + freshness:** construct a `QueryClient(clock: ManualClock())`,
  advance the clock to cross `staleTime` boundaries deterministically — no
  sleeping.
- **Component integration:** `AsyncTestHarness` (from Phase 20) with an injected
  `QueryClient`. `settle()` drives in-flight fetches and flushes re-renders to a
  fixed point. Inject fake fetch behavior via the component's defaulted dep
  (`Profile(userID: 1, api: FakeAPI())`).
- **Dedup:** assert that N concurrent `query()` calls for one key produce one
  `fetch()` invocation (a counting fake).
- **Invalidation:** assert prefix cascade, `exact` narrowing, and tag matching
  each refetch the right mounted observers and leave non-matches untouched.
- **Generation guard:** a superseded slow fetch must not clobber a newer fast
  fetch's result (the cache-level analogue of Phase 20's superseded-write test).

A `ManualClock` test double lives in the query test support (or `SwiflowTesting`,
decided in the plan).

---

## 11. Required core changes (`Swiflow`)

Small, surgical, all consistent with existing ambient/lifecycle patterns:

1. **Ambient current `(component, scheduler)`** set by the diff around each
   `body` eval, at `package` visibility (mirrors `AmbientEnvironment.current` /
   `TaskScope.currentScope`).
2. **Post-commit interest-flush hook** in the render path (`Renderer.renderOnce`
   and `TestRenderer`), so collected `query()` interests are handed to the
   client after the diff commits.
3. **Destroy-path unsubscribe notification**, so the client drops a component's
   subscriptions when its node unmounts.

These mirror exactly how Phase 20 wired `TaskScope` (currentScope around the
diff; cancel on destroy), so the integration surface is well-trodden.

---

## 12. Deferred sub-projects (separate specs)

- **#2 Mutations** — a `Mutation` analogue, optimistic updates with rollback,
  auto-invalidation of affected query keys/tags on success.
- **#3 Background & lifecycle** — refetch on window-focus / reconnect /
  polling interval; GC of unused entries (which also sweeps lingering
  subscriptions from §7.3); optional persistence.
- **Refinements** — `select` (with subscriber-level change-detection for the
  expensive-`body` case); object-subset key matching; auto-retry/backoff;
  variadic `query()` dependency composition.

---

## 13. Design rationale — key forks and why

- **Self-fetching typed key** (over call-site fetcher / client-registered
  fetcher): one fully-typed value carries identity + data type + fetch; the
  client can refetch/dedup/invalidate any key it holds. Deps-as-non-identity
  props preserve testability without splitting the definition across a
  registration step.
- **`[AnyHashable]` hierarchical key + prefix cascade + tags** (over an opaque
  Hashable struct identity, and over a relational parent-child edge graph): the
  prefix cascade gives TanStack's headline ergonomic; tags give relational
  ("everything on team 3") cascade *statelessly*. A maintained edge graph was
  rejected — a query cache holds only a transient, partial working set, so a
  graph pays cycle-detection + edge-lifecycle costs to reach exactly the same
  "currently-known entries" a stateless matcher already reaches.
- **`staleTime` default `.zero`** (over a non-zero default): correct-by-default
  freshness; SWR + dedup keep the cost to one background fetch with instant
  cached paint.
- **Shape B `query()` method returning a struct** (over a `@Query` property
  wrapper, over a `.query()`-into-`@State` modifier): free dynamic keys, no
  rules-of-hooks ordering, no new macro, and the struct carries SWR's two axes
  an enum cannot.
- **`select` deferred**: in Shape B you transform inline, and Swiflow's VNode
  diff already absorbs the no-op re-renders React needs `select` to prevent. The
  only genuine win (skipping an expensive `body`) needs subscriber-memoization
  machinery — out of scope for v1.
