# Query Core

Phase 21 adds `SwiflowQuery`, a TanStack-Query / SWR-style data layer for
Swiflow components. Instead of wiring `.task` + `@State` + a loading enum by
hand for every fetch, you declare a **`Query`** — a value that knows how to
fetch itself and where it lives in a shared cache — and consume it from `body`:

```swift
import SwiflowDOM
import SwiflowQuery

let u = query(UserByID(id: userID))
```

`query(_:)` returns a `QueryState` and subscribes the component to a per-root
`QueryClient` cache that handles deduplication, stale-while-revalidate, and
invalidation. No manual `.task`, no per-fetch loading flag.

> **Browser prerequisite.** `Swiflow.render(into:)` installs the
> `QueryClient` automatically on each render root (and wires the
> `JavaScriptEventLoop` global executor, as for `.task`). No setup is required
> in app code.

## The `Query` protocol

A `Query` is a small `@MainActor` value type describing one fetch:

```swift
public protocol Query {
    associatedtype Value: Equatable & Sendable
    var queryKey: QueryKey { get }
    var tags: Set<QueryTag> { get }              // default []
    var staleTime: Duration { get }              // default .zero
    var refetchInterval: Duration? { get }       // default nil (no polling)
    var refetchOnFocus: Bool { get }             // default true
    var retry: RetryPolicy { get }               // default .default (3 retries, exp backoff)
    var gcTime: Duration { get }                 // default .seconds(300)
    func fetch() async throws -> Value
}
```

Only `queryKey` and `fetch()` are required — everything else has a
protocol-extension default, so a minimal query is just those two.

The canonical demo query:

```swift
struct User: Equatable, Sendable { let id: Int; let name: String }

/// Simulated API: a non-identity dependency captured by the key.
struct FakeAPI: Sendable {
    func user(_ id: Int) async -> User {
        try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
        return User(id: id, name: "User #\(id)")
    }
}

struct UserByID: Query {
    let id: Int
    let api: FakeAPI
    var queryKey: QueryKey { ["users", .int(id)] }
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }

    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}
```

### `queryKey` — the typed hierarchical key

`QueryKey` is `[QueryKeyComponent]`, and `QueryKeyComponent` is `.string` or
`.int`. Both are `ExpressibleBy…Literal`, so a constant key reads naturally:

```swift
var queryKey: QueryKey { ["users", "active"] }   // two string literals
```

A **variable** `Int` needs the explicit case — a bare `id` would be ambiguous,
so write `.int(id)`:

```swift
var queryKey: QueryKey { ["users", .int(id)] }
```

The key is the cache identity *and* the dependency. Two queries with the same
key share one cache entry; changing the key (e.g. `id` goes 1 → 2) selects a
different entry and triggers a fetch for it. The hierarchy (`["users", …]`)
is what makes prefix invalidation possible — see below.

### `fetch` — and dependencies as stored properties

`fetch()` is the async work. Crucially, *everything the fetch depends on lives
on the query value as stored properties* — here, `id` and `api`. The `api` is
a **non-identity** dependency: it is not part of the key (two `UserByID(id: 1)`
values are "the same query" regardless of which `FakeAPI` instance they hold),
but the closure reads it. This is the seam you exploit in tests: inject a fake
API through a defaulted initializer parameter (`api: FakeAPI = FakeAPI()`).

### `tags` and `staleTime`

`tags` (default `[]`) is an orthogonal grouping axis for invalidation — a
`Set<QueryTag>` (`QueryTag` is `String`). Tag every user query `"users"` and
you can blow them all away with `invalidate(tag: "users")` regardless of key
shape.

`staleTime` (default `.zero`) controls how long fetched data is considered
fresh. With `.zero`, **every trigger revalidates**: the cached value (if any)
renders instantly while a refetch runs in the background — classic
stale-while-revalidate. A non-zero `staleTime` suppresses the background
refetch while the data is still within its freshness window.

## Consuming a query — `query(_:)` and `QueryState`

`query(_:)` is a `Component` method. Call it in `body`; it returns a
`QueryState<Value>`:

```swift
public struct QueryState<Value> {
    public var data: Value?
    public var error: (any Error)?
    public var isLoading: Bool      // first load, no data yet
    public var isFetching: Bool     // any fetch in flight (incl. background)
    public var isSuccess: Bool      // data != nil
}
```

The canonical component (`examples/QueryDemo`):

```swift
@Component
final class QueryDemo {
    @State var userID: Int = 1

    var body: VNode {
        let u = query(UserByID(id: userID))
        return div {
            h1("Query demo")
            div {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { span { text(" ⟳") } }
            }
            button("Next user", .on(.click) { self.userID += 1 })
        }
    }
}
```

`isLoading` vs `isFetching`: `isLoading` is true only for the *first* load of a
key, when there is no data to show yet. `isFetching` is true for *any* fetch in
flight — including the background revalidation over already-cached data — which
is exactly what the `⟳` spinner above tracks.

> **`span` takes children, not a string.** Unlike `p`/`h1`/`button`, the
> `span(_:)` factory has no String-convenience overload, so wrap text with the
> `text(…)` free function: `span { text(" ⟳") }`.

## The trigger model — fetches don't happen on every render

This is the central mental model. `body` is called on every re-render, and so
is `query(_:)` — but **calling `query(_:)` does not fetch**. A fetch is
triggered only by:

- **Mount** — the component first subscribes to a key with no fresh entry.
- **Key change** — `userID` bumps, so `queryKey` changes; the new key has no
  fresh entry, so it fetches.
- **`invalidate`** — a `QueryClient` call marks matching entries stale; live
  subscribers refetch.

A plain re-render with an unchanged key and a still-fresh entry does nothing.
With the default `.zero` `staleTime` the entry is immediately stale, so a
mount or key-change always revalidates — but the cached data, if present,
shows instantly while that refetch runs (stale-while-revalidate). This is why
clicking "Next user" back to a previously-loaded id shows it at once and only
flips the `⟳` spinner.

## Deduplication

Concurrent subscribers asking for the **same key** share one in-flight fetch.
If three components each `query(UserByID(id: 1))` in the same frame, exactly
one `fetch()` runs and all three receive its result. The cache keys the
in-flight `Task` by `queryKey`, so identity is structural, not per-call-site.

## Invalidation

Invalidation lives on `QueryClient` (`@MainActor`). Get one in app code by
holding a reference, or in tests by constructing it explicitly (below). Three
forms:

```swift
// Prefix cascade — every entry whose key starts with ["users"].
// Refetches users 1, 2, 3, … and any ["users", "active"] etc.
client.invalidate(["users"])

// Exact — only the entry with this exact key.
client.invalidate(["users", 1], exact: true)

// Tag — every entry whose `tags` contains "users", regardless of key shape.
client.invalidate(tag: "users")
```

Prefix invalidation is the everyday tool: after a mutation that could touch any
user, `invalidate(["users"])` revalidates the whole subtree. `exact: true`
narrows to one entry. Tags are the escape hatch for cross-cutting groups whose
keys don't share a prefix.

(Each invalidated entry is forced stale; entries with live subscribers refetch
immediately, the rest refetch lazily the next time something subscribes.)

## Testing

Use `AsyncTestHarness` from `SwiflowTesting` with an explicit `QueryClient`
driven by a `ManualClock`, so time and fetch settling are deterministic:

```swift
import Testing
import Swiflow
import SwiflowTesting
import SwiflowQuery

@Suite("QueryDemo")
@MainActor
struct QueryDemoTests {

    @Test func loadsFirstUser() async throws {
        let h = AsyncTestHarness(
            QueryDemo(),
            queryClient: QueryClient(clock: ManualClock())
        )
        try await h.settle()
        #expect(h.allText.contains("Loaded: User #1"))
    }

    @Test func bumpingKeyRefetches() async throws {
        let vm = QueryDemo()
        let h = AsyncTestHarness(
            vm,
            queryClient: QueryClient(clock: ManualClock())
        )
        try await h.settle()
        #expect(h.allText.contains("User #1"))

        vm.userID = 2     // change the key
        h.flush()         // reconcile: new key, spawn the next fetch
        try await h.settle()
        #expect(h.allText.contains("User #2"))
    }
}
```

`settle()` drives every in-flight fetch to completion and flushes the resulting
re-renders to a fixed point; `flush()` applies a synchronous `@State` mutation
made from test code so the diff reconciles the new key before you `settle()`.
The same `settle()`/`flush()` contract as the async-task harness — see
[async-tasks.md](async-tasks.md).

**Inject a fake through the defaulted dependency.** Because `api` is a stored
property with a default in the initializer, a test can hand the query a fake
without touching the component:

```swift
struct UserByID: Query {
    // …
    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}
```

A real-world variant takes the fetcher as an injected closure
(`@Sendable (Int) async -> User`) so the test supplies a synchronous,
no-latency stub and `settle()` returns in one round.

The full runnable demo is `examples/QueryDemo/`; run it with `swiflow dev`
from that directory.

## Beyond the read path

This guide covers the *read* half of the data layer. The rest has shipped and
builds on the same `QueryClient` cache and `Query` protocol:

- **Mutations** — `@MutationType` + `@MutationState`: a write path with
  optimistic updates (generation-guarded rollback via `OptimisticEdit`).
  Successful mutations refetch the keys `optimistic(_:)` declares by
  default; override `invalidations` for anything else, with type-referenced
  members that reuse your query types instead of restating key strings:
  `[.exact(TodoList()), .prefix(UserQuery(id: 1)), .tag("users")]`.
  `examples/TodoCRUD/` is the worked example.
- **Imperative refetch** — `QueryState.refetch()` on a query's snapshot
  (exact-invalidate semantics), and `Component.invalidate(query:/key:/tag:)`
  for handler-time invalidation without plumbing a `QueryClient` reference.
- **Cancellation at the network** — a superseded fetch (key change, fast
  typeahead churn) aborts its underlying request via `AbortController`;
  cancelled exchanges surface as `CancellationError`, never `HTTPError`.
- **Background refetch** — refetch on window focus (`refetchOnFocus`, on by
  default) and on a polling interval (`refetchInterval`). Both defer to the
  retry backoff after failures rather than hammering a failing endpoint.
- **Garbage collection** — cache entries with no subscribers are evicted
  after `gcTime` (default 5 minutes).
- **Auto-retry** — `retry: RetryPolicy`, default 3 attempts with exponential
  backoff.

Still deferred: **`select`** (a transformed/narrowed view of a query's data
without re-fetching) and refetch-on-reconnect.
