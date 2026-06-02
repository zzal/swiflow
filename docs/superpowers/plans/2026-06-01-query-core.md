# Query Core (Phase 21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `SwiflowQuery` — a typed, shared, auto-revalidating data-fetching/caching layer (TanStack-Query/SWR-style) built on the Phase 20 async foundation.

**Architecture:** A new `SwiflowQuery` module holds a `@MainActor QueryClient` cache keyed by typed hierarchical `QueryKey`s. Components consume via a `query(_:)` `Component` method returning a `QueryState<Value>` struct. The client conforms to a new query-agnostic `RenderObserver` boundary hook the diff fires around each component's `body` eval — that hook drives per-render subscription reconciliation and the refetch trigger model. Fetches dedup, ride a per-entry generation guard, and revalidate stale-while-serving. Invalidation cascades by key-prefix and by tag.

**Tech Stack:** Swift 6, swift-testing (`@Test`/`@Suite`/`#expect`), XCTest is not used here. `Duration` clock (monotonic). JavaScriptKit for the browser clock. Builds on `Swiflow`, `SwiflowTesting`, `SwiflowWeb`.

**Spec:** `docs/superpowers/specs/2026-06-01-query-core-design.md` (rev 3).

**Conventions for every task:**
- Test files use `@testable import SwiflowQuery` and `import Swiflow`; suites and tests are `@MainActor`.
- Run tests with: `swift test --filter <SuiteName>` (host toolchain; macOS local builds work — macOS CI is disabled).
- Commit after each task with the message shown. Work stays on the existing `query-core` branch.
- `QueryClient`, `Query`, and all client-touching code are `@MainActor` (the runtime is single-threaded under WASM; this keeps captured deps off any actor boundary).

---

## File Structure

**New module `Sources/SwiflowQuery/`:**
- `Keys.swift` — `QueryKeyComponent`, `QueryKey`, `QueryTag`, prefix-match helper.
- `Query.swift` — the `Query` protocol + defaults.
- `QueryState.swift` — the `QueryState<Value>` struct.
- `Clock.swift` — `QueryClock`, `SystemQueryClock`, `ManualClock`.
- `QueryEntry.swift` — internal `QueryEntry` reference type + `makeSnapshot`.
- `QueryClient.swift` — the `@MainActor` client: storage, subscriptions, fetch lifecycle, invalidation, reconciliation, `RenderObserver` conformance.
- `Query+Component.swift` — the `query(_:)` `Component` extension.

**New core file `Sources/Swiflow/Reactivity/RenderObserver.swift`:**
- `RenderObserver` package protocol + `RenderObserverBox` ambient.

**Modified core/runtime files:**
- `Sources/Swiflow/Diff/Diff.swift` — fire the boundary hook at the two `body`-eval bracket sites + the destroy path.
- `Sources/SwiflowTesting/TestRenderer.swift` — own a `QueryClient`, install it as the observer around diffs.
- `Sources/SwiflowTesting/AsyncTestHarness.swift` — `settle()` also awaits client in-flight fetches; inject a client.
- `Sources/SwiflowWeb/Renderer.swift` — own a default `QueryClient`, install it around `renderOnce`.
- `Package.swift` — add `SwiflowQuery` target + product + `SwiflowQueryTests`; add `SwiflowQuery` dep to `SwiflowWeb` and `SwiflowTesting`.

**New tests `Tests/SwiflowQueryTests/`** + additions to `Tests/SwiflowTests/`.

**Docs/example (Task 15):** `examples/QueryDemo/`, `docs/guides/query.md`, `CHANGELOG.md`, `README.md`, regenerated `Sources/SwiflowCLI/EmbeddedTemplates.swift`.

---

## Task 1: Module scaffold + typed keys

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowQuery/Keys.swift`
- Create: `Tests/SwiflowQueryTests/KeysTests.swift`

- [ ] **Step 1: Add the target, product, and test target to `Package.swift`**

In the `products:` array (after the `SwiflowTesting` library, line ~14) add:
```swift
        .library(name: "SwiflowQuery", targets: ["SwiflowQuery"]),
```
In the `targets:` array, after the `SwiflowRouter` target block, add:
```swift
        .target(
            name: "SwiflowQuery",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowQuery"
        ),
```
And after the `SwiflowRouterTests` test target block, add:
```swift
        .testTarget(
            name: "SwiflowQueryTests",
            dependencies: ["SwiflowQuery", "SwiflowTesting", "Swiflow"],
            path: "Tests/SwiflowQueryTests"
        ),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/SwiflowQueryTests/KeysTests.swift`:
```swift
import Testing
@testable import SwiflowQuery

@Suite("QueryKey")
struct KeysTests {
    @Test func literalsBuildComponents() {
        let k: QueryKey = ["users", 1]
        #expect(k == [.string("users"), .int(1)])
    }

    @Test func intAndStringAreDistinct() {
        #expect(QueryKeyComponent.int(1) != QueryKeyComponent.string("1"))
    }

    @Test func prefixMatches() {
        let entry: QueryKey = ["users", 1, "posts"]
        #expect(entry.hasPrefix(["users"]))
        #expect(entry.hasPrefix(["users", 1]))
        #expect(entry.hasPrefix(["users", 1, "posts"]))
    }

    @Test func nonPrefixDoesNotMatch() {
        let entry: QueryKey = ["users", 1]
        #expect(!entry.hasPrefix(["users", 2]))
        #expect(!entry.hasPrefix(["teams"]))
        #expect(!entry.hasPrefix(["users", 1, "posts"]))  // longer than entry
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter QueryKey`
Expected: FAIL — `SwiflowQuery` has no module / `QueryKey` undefined.

- [ ] **Step 4: Implement `Keys.swift`**

Create `Sources/SwiflowQuery/Keys.swift`:
```swift
// Sources/SwiflowQuery/Keys.swift

/// One level of a hierarchical query key. A closed, `Sendable`, `Hashable`
/// enum — the type-safe alternative to `AnyHashable` (no Int/Int64/String
/// confusion, debuggable, prefix-cascadable). Bools/enums/structs encode their
/// identity into a `.string` or `.int` component.
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

/// A hierarchical path identifying a query. `["users"]` is the 1-element case.
public typealias QueryKey = [QueryKeyComponent]

/// A cross-cutting invalidation family label.
public typealias QueryTag = String

extension Array where Element == QueryKeyComponent {
    /// True iff `self` starts with `prefix` (the positional-cascade rule).
    func hasPrefix(_ prefix: QueryKey) -> Bool {
        guard prefix.count <= count else { return false }
        return Array(self.prefix(prefix.count)) == prefix
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter QueryKey`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SwiflowQuery/Keys.swift Tests/SwiflowQueryTests/KeysTests.swift
git commit -m "feat(query): SwiflowQuery scaffold + typed QueryKeyComponent keys (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `Query` protocol + `QueryState`

**Files:**
- Create: `Sources/SwiflowQuery/Query.swift`
- Create: `Sources/SwiflowQuery/QueryState.swift`
- Create: `Tests/SwiflowQueryTests/QueryProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryProtocolTests.swift`:
```swift
import Testing
@testable import SwiflowQuery

@MainActor
private struct Echo: Query {
    let id: Int
    var queryKey: QueryKey { ["echo", .int(id)] }
    func fetch() async throws -> Int { id * 10 }
}

@Suite("Query")
@MainActor
struct QueryProtocolTests {
    @Test func defaultsAreEmptyTagsAndZeroStaleTime() {
        let q = Echo(id: 3)
        #expect(q.tags.isEmpty)
        #expect(q.staleTime == .zero)
        #expect(q.queryKey == ["echo", 3])
    }

    @Test func fetchReturnsValue() async throws {
        let v = try await Echo(id: 3).fetch()
        #expect(v == 30)
    }

    @Test func queryStateDefaultsAndSuccess() {
        let empty = QueryState<Int>()
        #expect(empty.data == nil)
        #expect(!empty.isSuccess)

        let loaded = QueryState<Int>(data: 42, isFetching: false)
        #expect(loaded.isSuccess)
        #expect(loaded.data == 42)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter Query`
Expected: FAIL — `Query` / `QueryState` undefined.

- [ ] **Step 3: Implement `Query.swift`**

Create `Sources/SwiflowQuery/Query.swift`:
```swift
// Sources/SwiflowQuery/Query.swift

/// A typed, self-fetching query: one value carries identity (`queryKey`),
/// behavior (`fetch`), and any captured dependencies (stored properties that
/// are NOT part of `queryKey`).
///
/// `@MainActor`-isolated to match the single-threaded WASM runtime: `fetch`
/// runs on the main actor, so captured dependencies never cross an actor
/// boundary and need not be `Sendable`. `Value` is `Sendable` for hygiene
/// (it may be returned across an `await` suspension) and `Equatable` for
/// forthcoming change-detection.
@MainActor
public protocol Query {
    associatedtype Value: Equatable & Sendable

    /// Hierarchical identity. Determines the cache slot and prefix-cascade
    /// matching. Must exclude captured dependencies.
    var queryKey: QueryKey { get }

    /// Cross-cutting invalidation families. Defaults to empty.
    var tags: Set<QueryTag> { get }

    /// Freshness window from the last successful fetch. Defaults to `.zero`
    /// (every *trigger* revalidates — but a plain re-render is not a trigger).
    var staleTime: Duration { get }

    /// Fetch the value. Cancellation is cooperative via the surrounding Task.
    func fetch() async throws -> Value
}

public extension Query {
    var tags: Set<QueryTag> { [] }
    var staleTime: Duration { .zero }
}
```

- [ ] **Step 4: Implement `QueryState.swift`**

Create `Sources/SwiflowQuery/QueryState.swift`:
```swift
// Sources/SwiflowQuery/QueryState.swift

/// The snapshot a component sees from `query(_:)`. A struct, not an enum,
/// because stale-while-revalidate needs two orthogonal axes at once: whether
/// data is present, and whether a fetch is in flight. Deliberately NOT
/// `Equatable` — it is never on the re-render path, and that dodges comparing
/// a non-`Equatable` `any Error`.
public struct QueryState<Value> {
    /// Last successful value, retained across refetch (the SWR property).
    public var data: Value?
    /// Last fetch error, if the most recent fetch failed. Read-only display data.
    public var error: (any Error)?
    /// No data yet AND a fetch is in flight (first load).
    public var isLoading: Bool
    /// A fetch is in flight, including background revalidation.
    public var isFetching: Bool

    public var isSuccess: Bool { data != nil }

    public init(
        data: Value? = nil,
        error: (any Error)? = nil,
        isLoading: Bool = false,
        isFetching: Bool = false
    ) {
        self.data = data
        self.error = error
        self.isLoading = isLoading
        self.isFetching = isFetching
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter Query`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowQuery/Query.swift Sources/SwiflowQuery/QueryState.swift Tests/SwiflowQueryTests/QueryProtocolTests.swift
git commit -m "feat(query): Query protocol + QueryState struct (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Clock abstraction

**Files:**
- Create: `Sources/SwiflowQuery/Clock.swift`
- Create: `Tests/SwiflowQueryTests/ClockTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/ClockTests.swift`:
```swift
import Testing
@testable import SwiflowQuery

@Suite("Clock")
struct ClockTests {
    @Test func manualClockStartsAndAdvances() {
        let clock = ManualClock(.seconds(10))
        #expect(clock.now() == .seconds(10))
        clock.advance(by: .seconds(5))
        #expect(clock.now() == .seconds(15))
        clock.advance(by: .milliseconds(500))
        #expect(clock.now() == .seconds(15) + .milliseconds(500))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter Clock`
Expected: FAIL — `ManualClock` undefined.

- [ ] **Step 3: Implement `Clock.swift`**

Create `Sources/SwiflowQuery/Clock.swift`:
```swift
// Sources/SwiflowQuery/Clock.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A monotonic time source. `now()` returns elapsed time since an arbitrary
/// fixed origin, so freshness comparisons can never be corrupted by a
/// wall-clock adjustment.
public protocol QueryClock {
    func now() -> Duration
}

/// Production clock. In the browser it reads `performance.now()` (monotonic,
/// millisecond resolution). On the host it uses `ContinuousClock` (monotonic).
/// Deterministic tests inject `ManualClock` instead; this type is smoke-tested
/// in the browser, not unit-tested.
public struct SystemQueryClock: QueryClock {
    public init() {}

    public func now() -> Duration {
        #if canImport(JavaScriptKit)
        let ms = JSObject.global.performance.object?.now?().number ?? 0
        return .milliseconds(Int(ms))
        #else
        return ContinuousClock().now - SystemQueryClock.hostOrigin
        #endif
    }

    #if !canImport(JavaScriptKit)
    private static let hostOrigin = ContinuousClock().now
    #endif
}

/// A test clock advanced explicitly. `@MainActor` use only (the client mutates
/// and reads it on the main actor).
public final class ManualClock: QueryClock {
    private var current: Duration
    public init(_ start: Duration = .zero) { self.current = start }
    public func now() -> Duration { current }
    public func advance(by delta: Duration) { current = current + delta }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter Clock`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/Clock.swift Tests/SwiflowQueryTests/ClockTests.swift
git commit -m "feat(query): monotonic QueryClock (System + Manual) (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `QueryEntry` + `makeSnapshot`

**Files:**
- Create: `Sources/SwiflowQuery/QueryEntry.swift`
- Create: `Tests/SwiflowQueryTests/QueryEntryTests.swift`

The cache stores one `QueryEntry` (a reference type) per key. `makeSnapshot`
projects an entry into a typed `QueryState`. An absent entry reads as
optimistic loading (we are about to fetch).

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryEntryTests.swift`:
```swift
import Testing
@testable import SwiflowQuery

@Suite("QueryEntry")
@MainActor
struct QueryEntryTests {
    @Test func absentEntryReadsAsLoading() {
        let s = makeSnapshot(from: nil, as: Int.self)
        #expect(s.data == nil)
        #expect(s.isLoading)
        #expect(s.isFetching)
    }

    @Test func presentValueNotFetchingIsSettled() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)
        #expect(!s.isLoading)
        #expect(!s.isFetching)
        #expect(s.isSuccess)
    }

    @Test func pendingFetchWithDataIsBackgroundFetching() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        e.hasPendingFetch = true
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)         // SWR: data retained
        #expect(!s.isLoading)        // has data → not "loading"
        #expect(s.isFetching)        // background revalidation
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryEntry`
Expected: FAIL — `QueryEntry` / `makeSnapshot` undefined.

- [ ] **Step 3: Implement `QueryEntry.swift`**

Create `Sources/SwiflowQuery/QueryEntry.swift`:
```swift
// Sources/SwiflowQuery/QueryEntry.swift

/// One cache slot. A reference type so the client can mutate it in place and
/// hold it across awaits. All access is on the `@MainActor` (via `QueryClient`).
@MainActor
final class QueryEntry {
    /// Last successful value, type-erased (`Value` varies per query).
    var value: Any?
    /// Last fetch error.
    var error: (any Error)?
    /// Clock time of the last SUCCESSFUL fetch; `nil` until first success or
    /// after a forced-stale invalidation.
    var lastFetched: Duration?
    /// Bumped on supersede/invalidate; a resolving fetch commits only if the
    /// entry's generation still matches the one it captured at spawn.
    var generation: Int = 0
    /// The currently running fetch, if any (dedup + cancellation handle).
    var inFlight: Task<Void, Never>?
    /// Observed-but-task-not-yet-spawned. Makes the snapshot report fetching
    /// between `observe` (during body) and `startFetch` (at reconcile).
    var hasPendingFetch: Bool = false
    /// Cross-cutting families this entry belongs to (from the latest query).
    var tags: Set<QueryTag> = []
    /// The latest query's fetch, capturing its latest dependencies. Used to
    /// refetch on invalidation. `@MainActor` so calling it needs no Sendable.
    var boxedFetch: (@MainActor () async throws -> Any)?
    /// Type-erased `Value` equality witness, captured from the concrete query.
    let valuesEqual: (Any?, Any?) -> Bool

    init(valuesEqual: @escaping (Any?, Any?) -> Bool) {
        self.valuesEqual = valuesEqual
    }
}

/// Project an entry into a typed snapshot. `nil` entry → optimistic loading.
@MainActor
func makeSnapshot<V>(from entry: QueryEntry?, as _: V.Type) -> QueryState<V> {
    guard let entry else {
        return QueryState(isLoading: true, isFetching: true)
    }
    let fetching = entry.inFlight != nil || entry.hasPendingFetch
    let data = entry.value as? V
    return QueryState(
        data: data,
        error: entry.error,
        isLoading: data == nil && fetching,
        isFetching: fetching
    )
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryEntry`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryEntry.swift Tests/SwiflowQueryTests/QueryEntryTests.swift
git commit -m "feat(query): QueryEntry cache slot + snapshot projection (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `QueryClient` storage + subscriptions + markDirty fanout

**Files:**
- Create: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Tests/SwiflowQueryTests/QueryClientSubscriptionTests.swift`

This task builds the client skeleton: the clock, the `entries`/`subscribers`/
`observed` maps, `subscribe`/`unsubscribe`, and `notify` (markDirty fanout with
dead-weak pruning). Fetch and reconcile come later.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryClientSubscriptionTests.swift`:
```swift
import Testing
import Swiflow
@testable import SwiflowQuery

/// A minimal hand-rolled component (no macro) usable as a subscriber owner.
@MainActor
private final class Dummy: Component {
    var body: VNode { .text("") }
}

@Suite("QueryClient/subscriptions")
@MainActor
struct QueryClientSubscriptionTests {
    private func makeOwner() -> AnyComponent { AnyComponent(Dummy()) }

    @Test func notifyMarksAllLiveSubscribers() {
        var marked: [ObjectIdentifier] = []
        let scheduler = SyncScheduler { marked.append(ObjectIdentifier($0.instance)) }
        let client = QueryClient(clock: ManualClock())

        let a = makeOwner(), b = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.subscribe(owner: b, scheduler: scheduler, to: ["k"])

        client.notify(["k"])
        #expect(marked.count == 2)
        #expect(marked.contains(ObjectIdentifier(a.instance)))
        #expect(marked.contains(ObjectIdentifier(b.instance)))
    }

    @Test func unsubscribeStopsNotifications() {
        var markCount = 0
        let scheduler = SyncScheduler { _ in markCount += 1 }
        let client = QueryClient(clock: ManualClock())
        let a = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.unsubscribe(ownerID: ObjectIdentifier(a.instance), from: ["k"])
        client.notify(["k"])
        #expect(markCount == 0)
    }

    @Test func subscribeIsIdempotentPerOwner() {
        var markCount = 0
        let scheduler = SyncScheduler { _ in markCount += 1 }
        let client = QueryClient(clock: ManualClock())
        let a = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])  // dup
        client.notify(["k"])
        #expect(markCount == 1)   // one mark, not two
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/subscriptions`
Expected: FAIL — `QueryClient` undefined.

- [ ] **Step 3: Implement `QueryClient.swift` (skeleton + subscriptions)**

Create `Sources/SwiflowQuery/QueryClient.swift`:
```swift
// Sources/SwiflowQuery/QueryClient.swift
import Swiflow

/// Owns the shared query cache, per-key subscriptions, the fetch lifecycle,
/// invalidation, and per-render subscription reconciliation. One instance per
/// render root, installed as that root's `RenderObserver` (Task 11/12/13).
@MainActor
public final class QueryClient {
    let clock: any QueryClock
    var entries: [QueryKey: QueryEntry] = [:]
    var subscribers: [QueryKey: [Subscriber]] = [:]
    /// Per owner-instance: the set of keys it observed in its last render.
    /// Drives per-render reconciliation (Task 9).
    var observed: [ObjectIdentifier: Set<QueryKey>] = [:]

    public init(clock: any QueryClock = SystemQueryClock()) {
        self.clock = clock
    }

    /// A weak reference to one subscribing component + its scheduler.
    struct Subscriber {
        weak var owner: AnyComponent?
        weak var scheduler: (any Scheduler)?
    }

    // MARK: - Subscriptions

    func subscribe(owner: AnyComponent, scheduler: any Scheduler, to key: QueryKey) {
        var subs = subscribers[key] ?? []
        let id = ObjectIdentifier(owner.instance)
        let already = subs.contains { sub in
            sub.owner.map { ObjectIdentifier($0.instance) } == id
        }
        if !already {
            subs.append(Subscriber(owner: owner, scheduler: scheduler))
        }
        subscribers[key] = subs
    }

    func unsubscribe(ownerID: ObjectIdentifier, from key: QueryKey) {
        guard var subs = subscribers[key] else { return }
        subs.removeAll { sub in
            guard let owner = sub.owner else { return true }   // prune dead
            return ObjectIdentifier(owner.instance) == ownerID
        }
        subscribers[key] = subs.isEmpty ? nil : subs
    }

    /// Mark every live subscriber of `key` dirty, pruning dead weak refs.
    func notify(_ key: QueryKey) {
        guard let subs = subscribers[key] else { return }
        var live: [Subscriber] = []
        for sub in subs {
            if let owner = sub.owner, let scheduler = sub.scheduler {
                scheduler.markDirty(owner)
                live.append(sub)
            }
        }
        subscribers[key] = live.isEmpty ? nil : live
    }

    /// True iff `key` currently has at least one live subscriber.
    func hasLiveSubscribers(_ key: QueryKey) -> Bool {
        guard let subs = subscribers[key] else { return false }
        return subs.contains { $0.owner != nil }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryClient/subscriptions`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientSubscriptionTests.swift
git commit -m "feat(query): QueryClient storage + subscriptions + markDirty fanout (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Fetch lifecycle — spawn, dedup, generation guard, completion

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Tests/SwiflowQueryTests/QueryClientFetchTests.swift`

`startFetch` spawns one `@MainActor` Task per entry (dedup), capturing the
entry's generation. `commitFetch` writes the result back only if the captured
generation still matches (drops superseded/invalidated results), updates
`lastFetched`, and notifies subscribers (start and completion both notify;
identical-output re-renders are absorbed by the VNode diff — see spec §3.3 note).
`inFlightTasks()` lets the test harness await all pending fetches.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryClientFetchTests.swift`:
```swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/fetch")
@MainActor
struct QueryClientFetchTests {
    private func awaitInFlight(_ client: QueryClient) async {
        for t in client.inFlightTasks() { await t.value }
    }

    @Test func startFetchPopulatesEntryAndNotifies() async {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())

        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { 99 }
        client.entries[["n"]] = entry
        client.subscribe(owner: owner, scheduler: scheduler, to: ["n"])

        client.startFetch(for: ["n"], entry: entry)
        await awaitInFlight(client)

        #expect(entry.value as? Int == 99)
        #expect(entry.inFlight == nil)
        #expect(entry.lastFetched != nil)
        #expect(marks >= 1)
    }

    @Test func secondStartFetchDedupes() async {
        var calls = 0
        let client = QueryClient(clock: ManualClock())
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { calls += 1; return 1 }
        client.entries[["n"]] = entry

        client.startFetch(for: ["n"], entry: entry)
        client.startFetch(for: ["n"], entry: entry)   // in-flight → ignored
        await awaitInFlight(client)
        #expect(calls == 1)
    }

    @Test func supersededResultIsDropped() async {
        let client = QueryClient(clock: ManualClock())
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { 1 }
        client.entries[["n"]] = entry

        client.startFetch(for: ["n"], entry: entry)
        // Supersede before the in-flight task commits.
        entry.generation += 1
        await awaitInFlight(client)
        #expect(entry.value == nil)   // stale result dropped by the generation guard
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/fetch`
Expected: FAIL — `startFetch` / `inFlightTasks` undefined.

- [ ] **Step 3: Implement the fetch lifecycle (append to `QueryClient.swift`)**

Add to `QueryClient`:
```swift
    // MARK: - Fetch lifecycle

    /// Spawn the entry's fetch if none is in flight (dedup). The task captures
    /// the entry's current generation and commits only if it still matches.
    func startFetch(for key: QueryKey, entry: QueryEntry) {
        guard entry.inFlight == nil, let boxedFetch = entry.boxedFetch else { return }
        entry.hasPendingFetch = false
        let generation = entry.generation
        entry.inFlight = Task { [weak self] in
            let result: Result<Any, any Error>
            do { result = .success(try await boxedFetch()) }
            catch { result = .failure(error) }
            self?.commitFetch(key: key, generation: generation, result: result)
        }
        // Reflect isFetching for any current subscribers (background spinner /
        // first-load). Identical-output re-renders are absorbed by the diff.
        notify(key)
    }

    private func commitFetch(key: QueryKey, generation: Int, result: Result<Any, any Error>) {
        guard let entry = entries[key] else { return }
        entry.inFlight = nil
        guard entry.generation == generation else { return }   // superseded → drop
        switch result {
        case .success(let value):
            entry.value = value
            entry.error = nil
            entry.lastFetched = clock.now()
        case .failure(let err):
            entry.error = err
            // Leave `lastFetched` unchanged: a failed fetch stays stale so the
            // next trigger retries.
        }
        notify(key)
    }

    /// All currently in-flight fetch tasks — awaited by the test harness.
    public func inFlightTasks() -> [Task<Void, Never>] {
        entries.values.compactMap { $0.inFlight }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryClient/fetch`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientFetchTests.swift
git commit -m "feat(query): fetch lifecycle — dedup + generation guard + completion (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `staleTime` trigger gating

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Tests/SwiflowQueryTests/QueryClientStalenessTests.swift`

`needsFetch` decides whether a *triggered* observation revalidates. A never-
successfully-fetched entry (`lastFetched == nil`) always fetches; otherwise it
fetches iff `now - lastFetched >= staleTime`. With `.zero`, every trigger
revalidates.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryClientStalenessTests.swift`:
```swift
import Testing
@testable import SwiflowQuery

@Suite("QueryClient/staleness")
@MainActor
struct QueryClientStalenessTests {
    @Test func neverFetchedAlwaysNeedsFetch() {
        let client = QueryClient(clock: ManualClock())
        let e = QueryEntry(valuesEqual: { _, _ in true })
        #expect(client.needsFetch(e, staleTime: .seconds(30)))
    }

    @Test func zeroStaleTimeIsAlwaysStale() {
        let clock = ManualClock(.seconds(100))
        let client = QueryClient(clock: clock)
        let e = QueryEntry(valuesEqual: { _, _ in true })
        e.lastFetched = .seconds(100)               // fetched "now"
        #expect(client.needsFetch(e, staleTime: .zero))
    }

    @Test func freshWithinStaleTimeDoesNotFetch() {
        let clock = ManualClock(.seconds(100))
        let client = QueryClient(clock: clock)
        let e = QueryEntry(valuesEqual: { _, _ in true })
        e.lastFetched = .seconds(90)                // 10s ago
        #expect(!client.needsFetch(e, staleTime: .seconds(30)))   // still fresh
        clock.advance(by: .seconds(25))             // now 35s old
        #expect(client.needsFetch(e, staleTime: .seconds(30)))    // now stale
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/staleness`
Expected: FAIL — `needsFetch` undefined.

- [ ] **Step 3: Implement `needsFetch` (append to `QueryClient.swift`)**

```swift
    // MARK: - Freshness

    /// Whether a *triggered* observation of this entry should revalidate.
    /// `lastFetched == nil` (never succeeded / forced stale) always fetches.
    func needsFetch(_ entry: QueryEntry, staleTime: Duration) -> Bool {
        guard let last = entry.lastFetched else { return true }
        return (clock.now() - last) >= staleTime
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryClient/staleness`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientStalenessTests.swift
git commit -m "feat(query): staleTime trigger gating (.zero = always revalidate) (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Invalidation — prefix/exact + tag

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Tests/SwiflowQueryTests/QueryClientInvalidateTests.swift`

`invalidate` forces matching entries stale (clears `lastFetched`, bumps
generation, cancels in-flight) and immediately refetches the ones with live
subscribers. Matching is prefix (or `exact`) over keys, or membership over tags.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryClientInvalidateTests.swift`:
```swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/invalidate")
@MainActor
struct QueryClientInvalidateTests {
    private func awaitInFlight(_ c: QueryClient) async {
        for t in c.inFlightTasks() { await t.value }
    }

    /// Seed a fetched entry with a counting fetch and a live subscriber.
    @discardableResult
    private func seed(_ client: QueryClient, _ key: QueryKey, tags: Set<QueryTag> = [],
                      counter: @escaping () -> Void) -> QueryEntry {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.boxedFetch = { counter(); return 1 }
        e.value = 1
        e.lastFetched = .zero
        e.tags = tags
        client.entries[key] = e
        client.subscribe(owner: AnyComponent(Dummy()),
                         scheduler: SyncScheduler { _ in }, to: key)
        return e
    }

    @Test func prefixCascadeRefetchesMatches() async {
        let client = QueryClient(clock: ManualClock())
        var u1 = 0, u1posts = 0, teams = 0
        seed(client, ["users", 1]) { u1 += 1 }
        seed(client, ["users", 1, "posts"]) { u1posts += 1 }
        seed(client, ["teams", 1]) { teams += 1 }

        client.invalidate(["users"])
        await awaitInFlight(client)

        #expect(u1 == 1)
        #expect(u1posts == 1)
        #expect(teams == 0)        // not under ["users"]
    }

    @Test func exactInvalidatesOnlyTheExactKey() async {
        let client = QueryClient(clock: ManualClock())
        var u1 = 0, u1posts = 0
        seed(client, ["users", 1]) { u1 += 1 }
        seed(client, ["users", 1, "posts"]) { u1posts += 1 }

        client.invalidate(["users", 1], exact: true)
        await awaitInFlight(client)
        #expect(u1 == 1)
        #expect(u1posts == 0)
    }

    @Test func tagCascadeRefetchesMatches() async {
        let client = QueryClient(clock: ManualClock())
        var a = 0, b = 0
        seed(client, ["users", 1], tags: ["team:3"]) { a += 1 }
        seed(client, ["users", 2], tags: ["team:9"]) { b += 1 }

        client.invalidate(tag: "team:3")
        await awaitInFlight(client)
        #expect(a == 1)
        #expect(b == 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/invalidate`
Expected: FAIL — `invalidate` undefined.

- [ ] **Step 3: Implement invalidation (append to `QueryClient.swift`)**

```swift
    // MARK: - Invalidation

    /// Force every entry whose key starts with `key` (or equals it when
    /// `exact`) stale, and refetch the ones with live subscribers.
    public func invalidate(_ key: QueryKey, exact: Bool = false) {
        for (entryKey, entry) in entries {
            let match = exact ? (entryKey == key) : entryKey.hasPrefix(key)
            if match { forceStaleAndRefetch(entryKey, entry) }
        }
    }

    /// Force every entry tagged `tag` stale, and refetch the live ones.
    public func invalidate(tag: QueryTag) {
        for (entryKey, entry) in entries where entry.tags.contains(tag) {
            forceStaleAndRefetch(entryKey, entry)
        }
    }

    private func forceStaleAndRefetch(_ key: QueryKey, _ entry: QueryEntry) {
        entry.lastFetched = nil          // force stale
        entry.generation += 1            // supersede any in-flight result
        entry.inFlight?.cancel()
        entry.inFlight = nil
        if hasLiveSubscribers(key) {
            startFetch(for: key, entry: entry)
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryClient/invalidate`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientInvalidateTests.swift
git commit -m "feat(query): prefix/exact + tag invalidation cascade (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Per-render reconciliation + component drop

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Tests/SwiflowQueryTests/QueryClientReconcileTests.swift`

`reconcile(owner:scheduler:observations:)` diffs a component's this-render key
set against its previous one: new keys subscribe + trigger (gated by
staleness); dropped keys unsubscribe; retained keys refresh `boxedFetch`/`tags`
without a trigger. `dropComponent` unsubscribes everything on unmount. The
`QueryObservation` value is what `observe()` (Task 11) records during body.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryClientReconcileTests.swift`:
```swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/reconcile")
@MainActor
struct QueryClientReconcileTests {
    private func awaitInFlight(_ c: QueryClient) async {
        for t in c.inFlightTasks() { await t.value }
    }
    private func obs(_ key: QueryKey, _ counter: @escaping () -> Void) -> QueryObservation {
        QueryObservation(
            key: key, tags: [], staleTime: .zero,
            boxedFetch: { counter(); return 1 },
            valuesEqual: { ($0 as? Int) == ($1 as? Int) }
        )
    }

    @Test func newKeySubscribesAndFetches() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        var calls = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        #expect(calls == 1)
        #expect(client.hasLiveSubscribers(["a"]))
    }

    @Test func droppedKeyUnsubscribes() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }

        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], {})])
        await awaitInFlight(client)
        // Next render observes a different key.
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["b"], {})])
        await awaitInFlight(client)

        #expect(!client.hasLiveSubscribers(["a"]))   // dropped
        #expect(client.hasLiveSubscribers(["b"]))
    }

    @Test func retainedKeyDoesNotRefetch() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }
        var calls = 0

        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        // Re-render observing the SAME key → not a trigger.
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        #expect(calls == 1)   // only the first observation fetched
    }

    @Test func dropComponentUnsubscribesAll() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["a"], {}), obs(["b"], {})])
        await awaitInFlight(client)
        client.dropComponent(owner)
        #expect(!client.hasLiveSubscribers(["a"]))
        #expect(!client.hasLiveSubscribers(["b"]))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/reconcile`
Expected: FAIL — `QueryObservation` / `reconcile` / `dropComponent` undefined.

- [ ] **Step 3: Implement reconciliation (append to `QueryClient.swift`)**

```swift
    // MARK: - Reconciliation

    /// One component's observation of one key during a render (recorded by
    /// `observe`). Carries everything reconcile needs to create the entry and
    /// trigger a fetch.
    struct QueryObservation {
        let key: QueryKey
        let tags: Set<QueryTag>
        let staleTime: Duration
        let boxedFetch: @MainActor () async throws -> Any
        let valuesEqual: (Any?, Any?) -> Bool
    }

    /// Diff `owner`'s this-render observations against its previous set.
    func reconcile(owner: AnyComponent, scheduler: (any Scheduler)?,
                   observations: [QueryObservation]) {
        let ownerID = ObjectIdentifier(owner.instance)
        let newKeys = Set(observations.map(\.key))
        let oldKeys = observed[ownerID] ?? []

        // Dropped keys → unsubscribe.
        for key in oldKeys.subtracting(newKeys) {
            unsubscribe(ownerID: ownerID, from: key)
        }
        observed[ownerID] = newKeys.isEmpty ? nil : newKeys

        var triggered = Set<QueryKey>()
        for ob in observations {
            let entry = entries[ob.key] ?? {
                let e = QueryEntry(valuesEqual: ob.valuesEqual)
                entries[ob.key] = e
                return e
            }()
            entry.tags = ob.tags
            entry.boxedFetch = ob.boxedFetch          // capture latest deps

            if let scheduler { subscribe(owner: owner, scheduler: scheduler, to: ob.key) }

            // Trigger only for NEW observations (mount / key-change), gated by
            // staleness; once per key per render.
            let isNew = !oldKeys.contains(ob.key)
            if isNew, !triggered.contains(ob.key), needsFetch(entry, staleTime: ob.staleTime) {
                triggered.insert(ob.key)
                entry.hasPendingFetch = true
                startFetch(for: ob.key, entry: entry)
            }
        }
    }

    /// Drop all of a component's subscriptions on unmount.
    func dropComponent(_ owner: AnyComponent) {
        let ownerID = ObjectIdentifier(owner.instance)
        for key in observed[ownerID] ?? [] {
            unsubscribe(ownerID: ownerID, from: key)
        }
        observed[ownerID] = nil
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter QueryClient/reconcile`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientReconcileTests.swift
git commit -m "feat(query): per-render subscription reconciliation + component drop (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Core `RenderObserver` boundary hook + diff wiring

**Files:**
- Create: `Sources/Swiflow/Reactivity/RenderObserver.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift` (lines ~252-257, ~422-427, ~638)
- Create: `Tests/SwiflowTests/RenderObserverTests.swift`

A general, query-agnostic seam: the diff fires `willEvaluate`/`didEvaluate`
around each component `body` eval, and `componentDidUnmount` from `destroy`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/RenderObserverTests.swift`:
```swift
import Testing
@testable import Swiflow

@MainActor
private final class Leaf: Component {
    let label: String
    init(_ label: String) { self.label = label }
    var body: VNode { .text(label) }
}

@MainActor
private final class Recorder: RenderObserver {
    var willCount = 0
    var didCount = 0
    var unmounts = 0
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) { willCount += 1 }
    func didEvaluate() { didCount += 1 }
    func componentDidUnmount(_ owner: AnyComponent) { unmounts += 1 }
}

@Suite("RenderObserver")
@MainActor
struct RenderObserverTests {
    @Test func firesAroundComponentBodyEval() {
        let rec = Recorder()
        RenderObserverBox.current = rec
        defer { RenderObserverBox.current = nil }

        var patches: [Patch] = []
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let desc = ComponentDescription(Leaf.self) { Leaf("hi") }
        _ = mount(.component(desc), into: &patches, handles: handles,
                  handlers: handlers, scheduler: nil, depth: 0, path: "", environment: .init())

        #expect(rec.willCount == 1)
        #expect(rec.didCount == 1)
    }
}
```

> Note: confirm the exact `mount(...)` signature against `Diff.swift` and adjust
> argument labels if needed; the point is to mount one `.component` node and
> assert one will/did pair fired.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RenderObserver`
Expected: FAIL — `RenderObserver` / `RenderObserverBox` undefined.

- [ ] **Step 3: Implement `RenderObserver.swift`**

Create `Sources/Swiflow/Reactivity/RenderObserver.swift`:
```swift
// Sources/Swiflow/Reactivity/RenderObserver.swift

/// A general, query-agnostic boundary hook the diff fires around each
/// component's `body` evaluation, plus on unmount. `SwiflowQuery` installs an
/// observer to drive per-render subscription reconciliation; core knows nothing
/// about queries. Mirrors `AmbientEnvironment` — installed per render root,
/// save/restored around each render.
@MainActor
package protocol RenderObserver: AnyObject {
    /// Before a component's `body` getter runs.
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?)
    /// After that getter returns (in a `defer`, mirroring the env restore).
    func didEvaluate()
    /// When a component anchor is destroyed.
    func componentDidUnmount(_ owner: AnyComponent)
}

/// The active render observer. Save/restored by each render root around its
/// render, exactly like `SwiflowTaskRuntime.currentScope`.
package enum RenderObserverBox {
    @MainActor package static var current: (any RenderObserver)?
}
```

- [ ] **Step 4: Wire the diff — mount site (`Diff.swift` ~252-257)**

Replace the body-eval block in the `.component` mount arm:
```swift
        let bodyVNode = handlers.withScope(scopeID) {
            let previousEnv = AmbientEnvironment.current
            AmbientEnvironment.current = environment
            RenderObserverBox.current?.willEvaluate(owner: instance, scheduler: scheduler)
            defer {
                AmbientEnvironment.current = previousEnv
                RenderObserverBox.current?.didEvaluate()
            }
            return instance.instance.body
        }
```

- [ ] **Step 5: Wire the diff — update site (`Diff.swift` ~422-427)**

Replace the body-eval block in the component-reuse update arm:
```swift
        let newBodyVNode = handlers.withScope(mounted.scopeID) {
            let previousEnv = AmbientEnvironment.current
            AmbientEnvironment.current = environment
            RenderObserverBox.current?.willEvaluate(owner: instance, scheduler: scheduler)
            defer {
                AmbientEnvironment.current = previousEnv
                RenderObserverBox.current?.didEvaluate()
            }
            return instance.instance.body
        }
```

- [ ] **Step 6: Wire the diff — destroy site (`Diff.swift` ~638-653)**

Inside `destroy(...)`, in the `if let any = node.component {` block, after the
`OnChangeStorage.remove(...)` line, add:
```swift
        RenderObserverBox.current?.componentDidUnmount(any)
```

- [ ] **Step 7: Run to verify it passes + run the full Swiflow suite**

Run: `swift test --filter RenderObserver`
Expected: PASS.
Run: `swift test --filter SwiflowTests`
Expected: PASS — the hook is null when no observer is installed, so existing diff/lifecycle tests are unaffected.

- [ ] **Step 8: Commit**

```bash
git add Sources/Swiflow/Reactivity/RenderObserver.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/RenderObserverTests.swift
git commit -m "feat(reactivity): query-agnostic RenderObserver boundary hook in the diff (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: `QueryClient` as `RenderObserver` + `observe` + `query(_:)`

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift`
- Create: `Sources/SwiflowQuery/Query+Component.swift`
- Create: `Tests/SwiflowQueryTests/QueryObserverConformanceTests.swift`

The client conforms to `RenderObserver` with a frame stack: `willEvaluate`
pushes a frame, `observe` appends to the top frame, `didEvaluate` pops and
reconciles. `query(_:)` finds the active client via `RenderObserverBox.current`
and calls `observe`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowQueryTests/QueryObserverConformanceTests.swift`:
```swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@MainActor
private struct N: Query {
    let id: Int
    var queryKey: QueryKey { ["n", .int(id)] }
    func fetch() async throws -> Int { id }
}

@Suite("QueryClient/observer")
@MainActor
struct QueryObserverConformanceTests {
    @Test func willObserveDidReconcilesAndFetches() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())

        client.willEvaluate(owner: owner, scheduler: SyncScheduler { _ in })
        let snap = client.observe(N(id: 5))     // during "body"
        #expect(snap.isLoading)                  // absent → optimistic loading
        client.didEvaluate()                     // reconcile → fetch

        for t in client.inFlightTasks() { await t.value }
        #expect(client.entries[["n", 5]]?.value as? Int == 5)
    }

    @Test func queryWithoutActiveClientReturnsLoading() {
        RenderObserverBox.current = nil
        let owner = Dummy()
        let snap = owner.query(N(id: 1))
        #expect(snap.isLoading)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter QueryClient/observer`
Expected: FAIL — `observe` / `willEvaluate` / `query` undefined.

- [ ] **Step 3: Implement the `RenderObserver` conformance + `observe` (append to `QueryClient.swift`)**

```swift
    // MARK: - RenderObserver (per-render observation frames)

    /// One in-progress component render's collected observations.
    private struct Frame {
        let owner: AnyComponent
        let scheduler: (any Scheduler)?
        var observations: [QueryObservation] = []
    }
    private var frames: [Frame] = []

    /// Called by `query(_:)` during `body`: record interest, return the current
    /// snapshot. Pure read otherwise — no fetch, no subscription mutation here.
    func observe<Q: Query>(_ q: Q) -> QueryState<Q.Value> {
        let key = q.queryKey
        let ob = QueryObservation(
            key: key,
            tags: q.tags,
            staleTime: q.staleTime,
            boxedFetch: { try await q.fetch() },
            valuesEqual: { ($0 as? Q.Value) == ($1 as? Q.Value) }
        )
        if !frames.isEmpty { frames[frames.count - 1].observations.append(ob) }
        return makeSnapshot(from: entries[key], as: Q.Value.self)
    }
}

extension QueryClient: RenderObserver {
    public func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) {
        frames.append(Frame(owner: owner, scheduler: scheduler))
    }

    public func didEvaluate() {
        guard let frame = frames.popLast() else { return }
        reconcile(owner: frame.owner, scheduler: frame.scheduler,
                  observations: frame.observations)
    }

    public func componentDidUnmount(_ owner: AnyComponent) {
        dropComponent(owner)
    }
}
```

> Note: the `}` after `observe(...)` closes the `QueryClient` class; the
> `extension QueryClient: RenderObserver` follows it. Place this block at the
> END of `QueryClient.swift`.

- [ ] **Step 4: Implement `query(_:)` (`Query+Component.swift`)**

Create `Sources/SwiflowQuery/Query+Component.swift`:
```swift
// Sources/SwiflowQuery/Query+Component.swift
import Swiflow

public extension Component {
    /// Observe a query from `body`. Returns the current cached snapshot and
    /// records interest with the active render root's client; the actual
    /// subscribe/fetch happens at the render boundary (`didEvaluate`).
    /// Outside a render (no active client) returns an optimistic loading state.
    func query<Q: Query>(_ q: Q) -> QueryState<Q.Value> {
        guard let client = RenderObserverBox.current as? QueryClient else {
            return QueryState(isLoading: true, isFetching: true)
        }
        return client.observe(q)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter QueryClient/observer`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Sources/SwiflowQuery/Query+Component.swift Tests/SwiflowQueryTests/QueryObserverConformanceTests.swift
git commit -m "feat(query): QueryClient RenderObserver conformance + query() Component method (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: TestRenderer + AsyncTestHarness wiring

**Files:**
- Modify: `Package.swift` (add `SwiflowQuery` dep to `SwiflowTesting`)
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`
- Modify: `Sources/SwiflowTesting/AsyncTestHarness.swift`
- Create: `Tests/SwiflowQueryTests/QueryIntegrationTests.swift` (first integration test)

`TestRenderer` owns a `QueryClient` and installs it as `RenderObserverBox.current`
around its diffs (mirroring its existing `SwiflowTaskRuntime.currentScope` set).
`AsyncTestHarness` accepts an injected client and `settle()` also awaits the
client's in-flight fetches.

- [ ] **Step 1: Add the dependency**

In `Package.swift`, change the `SwiflowTesting` target's `dependencies` from
`["Swiflow"]` to:
```swift
            dependencies: ["Swiflow", "SwiflowQuery"],
```

- [ ] **Step 2: Write the failing integration test**

Create `Tests/SwiflowQueryTests/QueryIntegrationTests.swift`:
```swift
import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

@MainActor
private struct User: Equatable, Sendable { let id: Int; let name: String }

@MainActor
private struct UserByID: Query {
    let id: Int
    let load: @Sendable (Int) -> String
    var queryKey: QueryKey { ["users", .int(id)] }
    func fetch() async throws -> User { User(id: id, name: load(id)) }
}

@MainActor @Component
private final class Profile {
    @State var userID: Int
    let load: @Sendable (Int) -> String
    init(userID: Int, load: @escaping @Sendable (Int) -> String) {
        self.userID = userID; self.load = load
    }
    var body: VNode {
        let u = query(UserByID(id: userID, load: load))
        return div {
            if let user = u.data { p(user.name) }
            else if u.isLoading { p("Loading…") }
        }
    }
}

@Suite("Query/integration")
@MainActor
struct QueryIntegrationTests {
    @Test func loadsOnMount() async throws {
        let client = QueryClient(clock: ManualClock())
        let h = AsyncTestHarness(Profile(userID: 1) { "User#\($0)" }, queryClient: client)
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter Query/integration`
Expected: FAIL — `AsyncTestHarness(_:queryClient:)` undefined.

- [ ] **Step 4: Wire `TestRenderer`**

In `Sources/SwiflowTesting/TestRenderer.swift`, add `import SwiflowQuery` at the
top. Add a stored property next to `taskScope`:
```swift
    /// This render root's query client, installed as the render observer around
    /// each diff so `query()` calls during `body` reach it.
    let queryClient: QueryClient
```
Change the initializer signature to accept it (default to a fresh client):
```swift
    init<C: Component>(_ instance: C, queryClient: QueryClient = QueryClient()) {
```
and assign `self.queryClient = queryClient` before the first `diff(...)`. Then,
in BOTH the `init` diff block and the `rerender(_:)` diff block, install the
observer alongside the existing task-scope set. In `init`, replace:
```swift
        SwiflowTaskRuntime.currentScope = taskScope
        defer {
            _testAmbientHandlers = nil
            SwiflowTaskRuntime.currentScope = nil
        }
```
with:
```swift
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            _testAmbientHandlers = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
```
In `rerender(_:)`, apply the same two added lines (set `RenderObserverBox.current
= queryClient` after the task-scope set; clear it in the `defer`).

- [ ] **Step 5: Wire `AsyncTestHarness`**

In `Sources/SwiflowTesting/AsyncTestHarness.swift`, add `import SwiflowQuery`.
Replace the initializer with one that threads a client through:
```swift
    public init<C: Component>(_ component: C, queryClient: QueryClient = QueryClient()) {
        let r = TestRenderer(component, queryClient: queryClient)
        self.renderer = r
        self.harness = TestHarness(r)
    }
```
In `settle()`, change the in-flight gather so it awaits BOTH task-scope tasks and
client fetches. Replace the body of the `while true` loop's gather:
```swift
            let taskHandles = renderer.taskScope.inFlightTasks()
            let queryHandles = renderer.queryClient.inFlightTasks()
            if taskHandles.isEmpty && queryHandles.isEmpty { break }
            rounds += 1
            if rounds > maxRounds { throw SettleError.exceededMaxRounds(maxRounds) }
            for t in taskHandles { await t.value }
            for t in queryHandles { await t.value }
            renderer.scheduler.flush()
```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter Query/integration`
Expected: PASS.
Run: `swift test --filter SwiflowTestingTests`
Expected: PASS — the default-client overloads keep existing call sites working.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/SwiflowTesting/TestRenderer.swift Sources/SwiflowTesting/AsyncTestHarness.swift Tests/SwiflowQueryTests/QueryIntegrationTests.swift
git commit -m "feat(testing): wire QueryClient into TestRenderer + AsyncTestHarness.settle (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 13: Browser Renderer wiring

**Files:**
- Modify: `Package.swift` (add `SwiflowQuery` dep to `SwiflowWeb`)
- Modify: `Sources/SwiflowWeb/Renderer.swift`

The browser Renderer owns a default `QueryClient` and installs it as the render
observer around `renderOnce()`, mirroring its existing
`SwiflowTaskRuntime.currentScope` install.

- [ ] **Step 1: Add the dependency**

In `Package.swift`, add `"SwiflowQuery"` to the `SwiflowWeb` target's
`dependencies` array (alongside `JavaScriptKit`/`JavaScriptEventLoop`):
```swift
                "Swiflow",
                "SwiflowQuery",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
```

- [ ] **Step 2: Add the client property + install (Renderer.swift)**

Add `import SwiflowQuery` near the top of `Renderer.swift` (inside the
`#if canImport(JavaScriptKit)`). Add a stored property next to `taskScope`:
```swift
    /// This root's query client, installed as the render observer around each
    /// render so `query()` during `body` reaches it.
    let queryClient = QueryClient()
```
In `renderOnce()`, where it currently sets the task scope:
```swift
        _currentRenderingRenderer = self
        SwiflowTaskRuntime.currentScope = taskScope
        defer {
            _currentRenderingRenderer = nil
            SwiflowTaskRuntime.currentScope = nil
        }
```
add the observer install:
```swift
        _currentRenderingRenderer = self
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            _currentRenderingRenderer = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
```

- [ ] **Step 3: Verify the host build compiles**

Run: `swift build`
Expected: builds clean (the `#if canImport(JavaScriptKit)` blocks compile out on
host; the dependency graph resolves).

- [ ] **Step 4: Verify the WASM build links**

Run from `examples/QueryDemo/` after Task 15 creates it — deferred. For now,
confirm the package graph builds:
Run: `swift build --target SwiflowWeb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/SwiflowWeb/Renderer.swift
git commit -m "feat(web): install per-root QueryClient as the render observer (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 14: End-to-end behavior tests

**Files:**
- Modify: `Tests/SwiflowQueryTests/QueryIntegrationTests.swift`

Cover the behaviors that only emerge through the full render path: refetch on
key change, dedup across two components, invalidation refetch, and SWR data
retention. Reuse the `User`/`UserByID`/`Profile` helpers from Task 12.

- [ ] **Step 1: Add the refetch-on-key-change test**

Append to `QueryIntegrationTests`:
```swift
    @Test func refetchesOnKeyChange() async throws {
        let client = QueryClient(clock: ManualClock())
        let vm = Profile(userID: 1) { "User#\($0)" }
        let h = AsyncTestHarness(vm, queryClient: client)
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        vm.userID = 2
        h.flush()                 // reconcile sees the new key
        try await h.settle()      // fetch for user 2
        #expect(h.allText.contains("User#2"))
    }
```

- [ ] **Step 2: Run it**

Run: `swift test --filter Query/integration`
Expected: PASS.

- [ ] **Step 3: Add the dedup test**

Add a counting fetch and two components sharing a key. Append:
```swift
    @MainActor @Component
    private final class Pair {
        let load: @Sendable (Int) -> String
        init(load: @escaping @Sendable (Int) -> String) { self.load = load }
        var body: VNode {
            let a = query(UserByID(id: 7, load: load))
            let b = query(UserByID(id: 7, load: load))   // same key, twice
            return div {
                p(a.data?.name ?? "…")
                p(b.data?.name ?? "…")
            }
        }
    }

    @Test func dedupesConcurrentSameKey() async throws {
        let client = QueryClient(clock: ManualClock())
        let counter = Counter()
        let h = AsyncTestHarness(
            Pair { id in counter.bump(); return "User#\(id)" },
            queryClient: client
        )
        try await h.settle()
        #expect(counter.value == 1)   // one fetch despite two observations
    }
```
Add a tiny main-actor counter helper at file scope:
```swift
@MainActor private final class Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
```

- [ ] **Step 4: Run it**

Run: `swift test --filter Query/integration`
Expected: PASS.

- [ ] **Step 5: Add the invalidation refetch test**

Append:
```swift
    @Test func invalidateRefetchesMountedObserver() async throws {
        let client = QueryClient(clock: ManualClock())
        let counter = Counter()
        let h = AsyncTestHarness(
            Profile(userID: 1) { id in counter.bump(); return "User#\(id)" },
            queryClient: client
        )
        try await h.settle()
        #expect(counter.value == 1)

        client.invalidate(["users", 1])
        try await h.settle()
        #expect(counter.value == 2)   // forced refetch
    }
```

- [ ] **Step 6: Run it + the whole query suite**

Run: `swift test --filter Query/integration`
Expected: PASS.
Run: `swift test --filter SwiflowQueryTests`
Expected: PASS (all query tests).

- [ ] **Step 7: Commit**

```bash
git add Tests/SwiflowQueryTests/QueryIntegrationTests.swift
git commit -m "test(query): e2e — key-change refetch, dedup, invalidate refetch (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 15: Example app + docs + template embedding

**Files:**
- Create: `examples/QueryDemo/` (Package.swift, Sources/App/App.swift, index.html, swiflow-driver.js, swiflow-sw.js, README.md, .gitignore)
- Create: `docs/guides/query.md`
- Modify: `CHANGELOG.md`, `README.md`
- Regenerate: `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Scaffold the example from HelloWorld**

Copy the structure of `examples/HelloWorld/` (Package.swift, index.html,
swiflow-driver.js, swiflow-sw.js, .gitignore) into `examples/QueryDemo/`,
renaming the product/app to `App`. The example's `Package.swift` must depend on
`SwiflowWeb` and `SwiflowQuery` (path-based, like other examples).

- [ ] **Step 2: Write `examples/QueryDemo/Sources/App/App.swift`**

```swift
// Sources/App/App.swift
import SwiflowWeb
import SwiflowQuery

struct User: Equatable, Sendable { let id: Int; let name: String }

/// Simulated API: a non-identity dependency captured by the key.
struct FakeAPI: Sendable {
    func user(_ id: Int) async -> User {
        try? await Task.sleep(nanoseconds: 400_000_000)
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

@MainActor @Component
final class QueryDemo {
    @State var userID: Int = 1

    var body: VNode {
        let u = query(UserByID(id: userID))
        return div {
            h1("Query demo")
            div {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { span(" ⟳") }
            }
            button("Next user", .on(.click) { self.userID += 1 })
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { QueryDemo() }
    }
}
```

- [ ] **Step 3: Build the example for WASM**

Run from `examples/QueryDemo/`:
`swift package --swift-sdk swift-6.3-RELEASE_wasm js --use-cdn --product App -c release`
Expected: produces `.build/plugins/PackageToJS/outputs/Package/App.wasm`.

- [ ] **Step 4: Write `docs/guides/query.md`**

Write a guide covering: the `Query` protocol (key/fetch/deps-as-properties),
`query(_:)` + `QueryState`, the `.zero` staleTime + SWR trigger model,
`invalidate` (prefix + tag), and testing with `AsyncTestHarness` + `ManualClock`.
Mirror the structure of `docs/guides/async-tasks.md`. Include the canonical
`UserByID`/`QueryDemo` example and a testing example using
`AsyncTestHarness(_, queryClient:)`.

- [ ] **Step 5: Update `CHANGELOG.md` and `README.md`**

Add a "Query Core (Phase 21)" section to `CHANGELOG.md` summarizing: typed
queries, shared cache, dedup, SWR, prefix+tag invalidation, `query()` consumption.
Update the status/feature list in `README.md` to mention `SwiflowQuery`.

- [ ] **Step 6: Regenerate embedded templates**

Run: `swift scripts/embed-templates.swift`
Expected: `Sources/SwiflowCLI/EmbeddedTemplates.swift` updates (the freshness
test guards this — see next step).

- [ ] **Step 7: Run the embed-freshness + full suite**

Run: `swift test --filter TemplateEmbedderTests`
Expected: PASS (bit-for-bit fresh).
Run: `swift test`
Expected: PASS — full suite green.

- [ ] **Step 8: Commit**

```bash
git add examples/QueryDemo docs/guides/query.md CHANGELOG.md README.md Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "docs(query): QueryDemo example, guide, changelog, embedded template (Phase 21)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (each spec section → task):**
- §3.1 keys → Task 1. §3.2 Query → Task 2. §3.3 QueryState → Task 2. §3.4 clock → Task 3. §3.5 deps-as-properties → Tasks 2/12/15 (examples). §4 `query()` → Task 11. §5 data flow/triggers → Tasks 6/7/9/14. §6 invalidation → Task 8. §7.1 boundary hook → Task 10. §7.2 reconcile → Tasks 9/11. §7.3 no-lingering → Task 9 (dropped-key + dropComponent). §7.4 generation guard → Task 6. §7.5 concurrency → `@MainActor` throughout. §8 per-root client → Tasks 12/13. §9 errors → Task 6 (`commitFetch` failure arm). §10 testing → Tasks 3/12/14. §11 core changes → Tasks 10/12/13. All covered.
- **Deferred (correctly absent):** mutations, background/focus/interval, GC, `select`, auto-retry, object-subset matching.

**Placeholder scan:** No TBD/TODO. Every code step shows complete code; the two "confirm the exact signature" notes (Task 10 `mount(...)`, Task 12 diff blocks) point at real, named sites with the transformation shown — adaptation, not invention.

**Type consistency:** `QueryKey = [QueryKeyComponent]`; `QueryClient.observe<Q: Query>(_:) -> QueryState<Q.Value>`; `query<Q: Query>(_:) -> QueryState<Q.Value>`; `QueryEntry.boxedFetch: (@MainActor () async throws -> Any)?` matches `QueryObservation.boxedFetch`; `RenderObserver.willEvaluate(owner:scheduler:)` (scheduler optional) matches the diff call sites (`scheduler` is `(any Scheduler)?` there) and the `Recorder`/`QueryClient` witnesses; `inFlightTasks() -> [Task<Void, Never>]` used identically in client tests, invalidate tests, and `settle()`. `startFetch(for:entry:)`, `needsFetch(_:staleTime:)`, `reconcile(owner:scheduler:observations:)`, `dropComponent(_:)` names are stable across their defining and using tasks.

**One risk flagged for the implementer:** Task 10's `RenderObserver.willEvaluate(owner:scheduler:)` takes an **optional** scheduler, because the diff's `scheduler` argument is `(any Scheduler)?`. The `Recorder` test double and the `QueryClient` conformance must both use the optional signature. If the real `mount`/`update` signatures pass a non-optional scheduler, widen to optional at the witness and the diff call consistently.
