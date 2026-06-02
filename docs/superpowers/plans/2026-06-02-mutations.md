# Swiflow Mutations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add writes to the data layer — a self-describing `Mutation`, consumed via `@MutationState` + a `$`-projected `MutationHandle`, with declarative optimistic updates (auto snapshot/rollback) and auto-invalidation, building on the shipped `SwiflowQuery` Query Core.

**Architecture:** All new types live in `SwiflowQuery`. A `Mutation` protocol (`Input`/`Output`/`perform`/`optimistic`/`invalidations`) is the definition; a persistent `MutationRuntime<M>` class holds reactive state and runs the single engine path (`run` → `Result`, never throws); a transient `MutationHandle<M>` struct is the `$create` projection (forwards `mutate`/`mutateAsync`/`reset`). The `@MutationState` peer macro emits the runtime + projection; the `@Component` macro is extended to wire the `QueryClient` into each runtime at mount via its `bind`. Optimistic edits use a new package-internal `setQueryData` on `QueryClient` that cancels in-flight fetches + bumps the entry generation so the optimistic value survives concurrent revalidation.

**Tech Stack:** Swift 6 (language mode v6), `@MainActor` throughout, swift-syntax macros (`SwiflowMacrosPlugin`), swift-testing (`@Test`/`@Suite`/`#expect`). Spec: `docs/superpowers/specs/2026-06-02-mutations-design.md` (rev 3).

**Design source of truth:** the rev-3 spec. Read §3–§11 before starting. Key decisions baked in below: handle on `$`-projection (not `create`); `run` returns `Result`; `setQueryData` cancels+bumps-generation; client wired at mount; **macro wiring uses the inline-in-`bind` shape (spec option (a))** — chosen over the descriptor array because, having inspected `ComponentMacro`, inline emission adds no new emitted member and carries identical coupling, so it is the lower-risk shape for v1 (typical N=1 mutation/component).

**Branch:** create/execute on a `mutations` branch (or a worktree via `superpowers:using-git-worktrees` at execution time). Do NOT work on `main`.

---

## Task 1: `Invalidation` enum + `OptimisticEdit` (pure types)

**Files:**
- Create: `Sources/SwiflowQuery/Invalidation.swift`
- Create: `Sources/SwiflowQuery/OptimisticEdit.swift`
- Test: `Tests/SwiflowQueryTests/MutationCoreTypesTests.swift`

These two have no dependencies on the rest of the feature, so they go first; `Mutation` (Task 2) depends on both.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationCoreTypesTests.swift
import Testing
@testable import SwiflowQuery

@MainActor
private struct Count: Query {
    var queryKey: QueryKey { ["count"] }
    func fetch() async throws -> Int { 0 }
}

@Suite("Mutation/coreTypes")
@MainActor
struct MutationCoreTypesTests {
    @Test func invalidationCasesEquate() {
        #expect(Invalidation.prefix(["a"]) == .prefix(["a"]))
        #expect(Invalidation.exact(["a", 1]) != .prefix(["a", 1]))
    }

    @Test func updateCarriesKeyAndTransforms() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        #expect(edit.key == ["count"])
        #expect((edit.apply(10) as? Int) == 11)
    }

    @Test func updateNoOpsOnAbsentOrMismatchedValue() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        #expect(edit.apply(nil) == nil)            // absent → no-op
        #expect(edit.apply("not an int") == nil)   // type mismatch → no-op
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowQueryTests.MutationCoreTypesTests`
Expected: FAIL — `cannot find 'Invalidation'` / `'OptimisticEdit'`.

- [ ] **Step 3: Write `Invalidation.swift`**

```swift
// Sources/SwiflowQuery/Invalidation.swift

/// A declarative invalidation target a `Mutation` runs on success. Maps onto
/// the shipped `QueryClient.invalidate(_:exact:)` / `invalidate(tag:)`.
public enum Invalidation: Equatable, Sendable {
    case prefix(QueryKey)
    case exact(QueryKey)
    case tag(QueryTag)
}
```

- [ ] **Step 4: Write `OptimisticEdit.swift`**

```swift
// Sources/SwiflowQuery/OptimisticEdit.swift

/// One declarative cache edit applied before a mutation's `perform` resolves.
/// Constructed from a typed `Query` so the transform is fully type-checked; the
/// query instance supplies both the cache key and the value type.
public struct OptimisticEdit {
    let key: QueryKey
    /// Type-erased transform: current value (`Any?`) → new value, or `nil` to
    /// skip the write (no entry / type mismatch). `nil` ⇒ no snapshot recorded.
    let apply: (Any?) -> Any?

    /// Transform the cached value of `query`. No-op when the entry holds no
    /// value of `Q.Value`.
    @MainActor
    public static func update<Q: Query>(
        _ query: Q,
        _ transform: @escaping (Q.Value) -> Q.Value
    ) -> OptimisticEdit {
        let key = query.queryKey
        return OptimisticEdit(key: key) { current in
            guard let value = current as? Q.Value else { return nil }
            return transform(value)
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SwiflowQueryTests.MutationCoreTypesTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowQuery/Invalidation.swift Sources/SwiflowQuery/OptimisticEdit.swift Tests/SwiflowQueryTests/MutationCoreTypesTests.swift
git commit -m "feat(query): Invalidation enum + OptimisticEdit.update"
```

---

## Task 2: `Mutation` protocol

**Files:**
- Create: `Sources/SwiflowQuery/Mutation.swift`
- Test: `Tests/SwiflowQueryTests/MutationProtocolTests.swift`

Depends on `Invalidation` + `OptimisticEdit` from Task 1.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationProtocolTests.swift
import Testing
@testable import SwiflowQuery

@MainActor
private struct Save: Mutation {
    let sink: @MainActor @Sendable (String) -> Int
    func perform(_ input: String) async throws -> Int { sink(input) }
}

@Suite("Mutation/protocol")
@MainActor
struct MutationProtocolTests {
    @Test func defaultsAreEmpty() {
        let m = Save { _ in 1 }
        #expect(m.optimistic("x").isEmpty)
        #expect(m.invalidations(input: "x", output: 1).isEmpty)
    }

    @Test func performRuns() async throws {
        let m = Save { $0.count }
        let out = try await m.perform("abcd")
        #expect(out == 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowQueryTests.MutationProtocolTests`
Expected: FAIL — `cannot find type 'Mutation'`.

- [ ] **Step 3: Write `Mutation.swift`**

```swift
// Sources/SwiflowQuery/Mutation.swift

/// A typed, self-describing write. Mirrors `Query`: one value carries behavior
/// (`perform`), captured dependencies (stored properties), and declarations of
/// its effects (`optimistic`, `invalidations`). `@MainActor`-isolated so
/// captured dependencies never cross an actor boundary.
@MainActor
public protocol Mutation {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    /// Run the write. Cancellation is cooperative via the surrounding Task.
    func perform(_ input: Input) async throws -> Output

    /// Cache edits applied before `perform` resolves; the engine snapshots,
    /// applies, and rolls them back on failure. Defaults to none.
    func optimistic(_ input: Input) -> [OptimisticEdit]

    /// What to refresh on success — a function of input AND the server output,
    /// so it can target the freshly-created entity. Defaults to none.
    func invalidations(input: Input, output: Output) -> [Invalidation]
}

public extension Mutation {
    func optimistic(_ input: Input) -> [OptimisticEdit] { [] }
    func invalidations(input: Input, output: Output) -> [Invalidation] { [] }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SwiflowQueryTests.MutationProtocolTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/Mutation.swift Tests/SwiflowQueryTests/MutationProtocolTests.swift
git commit -m "feat(query): Mutation protocol (perform + optimistic + invalidations)"
```

---

## Task 3: `QueryClient` cache primitives (`getQueryData`/`setQueryData`)

**Files:**
- Create: `Sources/SwiflowQuery/QueryClient+Cache.swift`
- Test: `Tests/SwiflowQueryTests/QueryClientCacheTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/QueryClientCacheTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/cache")
@MainActor
struct QueryClientCacheTests {
    /// Seed an entry by reconciling a single observation for `key` with value V.
    private func seed(_ client: QueryClient, _ key: QueryKey, _ value: Int) async {
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: key, tags: [], staleTime: .zero,
                boxedFetch: { value },
                valuesEqual: { ($0 as? Int) == ($1 as? Int) })])
        for t in client.inFlightTasks() { await t.value }   // let the fetch settle
        _ = owner   // retain through settle
    }

    @Test func setThenGet() async {
        let client = QueryClient(clock: ManualClock())
        await seed(client, ["n"], 1)
        client.setQueryData(["n"], 42)
        #expect(client.getQueryData(["n"], as: Int.self) == 42)
        #expect(client.getQueryDataErased(["n"]) as? Int == 42)
    }

    @Test func setIsNoOpOnAbsentEntry() {
        let client = QueryClient(clock: ManualClock())
        client.setQueryData(["missing"], 99)               // no entry → no-op
        #expect(client.getQueryData(["missing"], as: Int.self) == nil)
    }

    @Test func setBumpsGenerationAndCancelsInFlight() async {
        let client = QueryClient(clock: ManualClock())
        await seed(client, ["n"], 1)
        let entry = client.entries[["n"]]!
        let genBefore = entry.generation
        client.setQueryData(["n"], 7)
        #expect(entry.generation == genBefore + 1)         // superseded
        #expect(entry.inFlight == nil)
        #expect(entry.lastFetched == nil)                  // left stale
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowQueryTests.QueryClientCacheTests`
Expected: FAIL — `value of type 'QueryClient' has no member 'setQueryData'`.

- [ ] **Step 3: Write `QueryClient+Cache.swift`**

```swift
// Sources/SwiflowQuery/QueryClient+Cache.swift
import Swiflow

// Package-internal cache read/write used by the mutation engine (§11). NOT a
// public imperative-cache-surgery surface in v1.
extension QueryClient {
    /// Typed read of the current cached value at `key`.
    package func getQueryData<V>(_ key: QueryKey, as _: V.Type) -> V? {
        entries[key]?.value as? V
    }

    /// Type-erased read used by the optimistic engine for snapshots.
    package func getQueryDataErased(_ key: QueryKey) -> Any? {
        entries[key]?.value
    }

    /// Write `value` into the entry at `key`, supersede any in-flight fetch, and
    /// notify observers. No-op when no entry exists. Leaves the entry stale so a
    /// later `invalidate` still refetches (the optimistic value is provisional).
    ///
    /// The generation bump + cancel mirror `forceStaleAndRefetch`: a concurrent
    /// fetch that resolves afterward is dropped by `commitFetch`'s generation
    /// guard, so it can't clobber the optimistic value (spec §11, B3).
    package func setQueryData(_ key: QueryKey, _ value: Any?) {
        guard let entry = entries[key] else { return }
        entry.generation += 1
        entry.inFlight?.cancel()
        entry.inFlight = nil
        entry.value = value
        entry.error = nil
        entry.lastFetched = nil
        notify(key)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SwiflowQueryTests.QueryClientCacheTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient+Cache.swift Tests/SwiflowQueryTests/QueryClientCacheTests.swift
git commit -m "feat(query): package-internal getQueryData/setQueryData (cancel+gen-bump)"
```

---

## Task 4: Mutation in-flight task registry on `QueryClient`

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (add storage; extend `inFlightTasks()`)
- Modify: `Sources/SwiflowQuery/QueryClient+Cache.swift` (token methods)
- Test: `Tests/SwiflowQueryTests/MutationTaskRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationTaskRegistryTests.swift
import Testing
@testable import SwiflowQuery

@Suite("QueryClient/mutationTasks")
@MainActor
struct MutationTaskRegistryTests {
    @Test func registeredTaskAppearsInFlightThenSelfRemoves() async {
        let client = QueryClient(clock: ManualClock())
        let token = client.nextMutationTaskToken()
        let started = client.inFlightTasks().count
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(1))
            client.removeMutationTask(token)
        }
        client.storeMutationTask(token, task)
        #expect(client.inFlightTasks().count == started + 1)
        await task.value
        #expect(client.inFlightTasks().count == started)   // self-removed by token
    }

    @Test func tokensAreUnique() {
        let client = QueryClient(clock: ManualClock())
        #expect(client.nextMutationTaskToken() != client.nextMutationTaskToken())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowQueryTests.MutationTaskRegistryTests`
Expected: FAIL — no `nextMutationTaskToken`.

- [ ] **Step 3: Add storage + extend `inFlightTasks()` in `QueryClient.swift`**

In the stored-property block near the top of `QueryClient` (after `var observed: ...`), add:

```swift
    /// In-flight mutation driving tasks, token-keyed so a task self-removes by
    /// token (NOT index — index removal would race a concurrent removal).
    var mutationTasks: [Int: Task<Void, Never>] = [:]
    var nextMutationToken = 0
```

Replace the existing `inFlightTasks()` body:

```swift
    package func inFlightTasks() -> [Task<Void, Never>] {
        entries.values.compactMap { $0.inFlight } + Array(mutationTasks.values)
    }
```

- [ ] **Step 4: Add token methods in `QueryClient+Cache.swift`**

Append to the `extension QueryClient` in `QueryClient+Cache.swift`:

```swift
    package func nextMutationTaskToken() -> Int {
        defer { nextMutationToken += 1 }
        return nextMutationToken
    }
    package func storeMutationTask(_ token: Int, _ task: Task<Void, Never>) {
        mutationTasks[token] = task
    }
    package func removeMutationTask(_ token: Int) {
        mutationTasks[token] = nil
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SwiflowQueryTests.MutationTaskRegistryTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowQuery/QueryClient.swift Sources/SwiflowQuery/QueryClient+Cache.swift Tests/SwiflowQueryTests/MutationTaskRegistryTests.swift
git commit -m "feat(query): token-keyed mutation task registry in inFlightTasks()"
```

---

## Task 5: `MutationStatus` + `MutationRuntime` + `MutationHandle` (engine: success/failure)

**Files:**
- Create: `Sources/SwiflowQuery/MutationState.swift`
- Test: `Tests/SwiflowQueryTests/MutationEngineTests.swift`

This task builds the engine with the success/failure transitions and the handle's `mutate`/`mutateAsync`/`reset`. Optimism + invalidation come in Task 6 (the `run` body is written complete here but its optimism/invalidation use the methods already available from Tasks 2–3).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationEngineTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class Dummy: Component { var body: VNode { .text("") } }
private enum Boom: Error { case nope }

@MainActor
private struct Save: Mutation {
    let run: @MainActor @Sendable (String) async throws -> Int
    func perform(_ input: String) async throws -> Int { try await run(input) }
}

@Suite("Mutation/engine")
@MainActor
struct MutationEngineTests {
    private func wiredHandle(_ m: Save, _ client: QueryClient)
        -> (MutationHandle<Save>, MutationRuntime<Save>) {
        let rt = MutationRuntime<Save>()
        rt.wire(owner: AnyComponent(Dummy()), scheduler: SyncScheduler { _ in }, client: client)
        return (MutationHandle(runtime: rt, mutation: m), rt)
    }
    private func settle(_ c: QueryClient) async { for t in c.inFlightTasks() { await t.value } }

    @Test func successSetsData() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { $0.count }, client)
        h.mutate("abcd")
        await settle(client)
        #expect(rt.status == .success)
        #expect(rt.data == 4)
        #expect(rt.error == nil)
    }

    @Test func failureSetsError() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { _ in throw Boom.nope }, client)
        h.mutate("x")
        await settle(client)
        #expect(rt.status == .error)
        #expect(rt.error != nil)
        #expect(rt.data == nil)
    }

    @Test func mutateAsyncReturnsAndRethrows() async throws {
        let client = QueryClient(clock: ManualClock())
        let (ok, _) = wiredHandle(Save { $0.count }, client)
        let out = try await ok.mutateAsync("hello")
        #expect(out == 5)

        let (bad, rt) = wiredHandle(Save { _ in throw Boom.nope }, client)
        await #expect(throws: Boom.self) { try await bad.mutateAsync("x") }
        #expect(rt.status == .error)        // same error also stored on the handle
    }

    @Test func resetReturnsToIdle() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { $0.count }, client)
        h.mutate("ab"); await settle(client)
        #expect(rt.status == .success)
        h.reset()
        #expect(rt.status == .idle)
        #expect(rt.data == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowQueryTests.MutationEngineTests`
Expected: FAIL — `cannot find 'MutationRuntime'` / `'MutationHandle'`.

- [ ] **Step 3: Write `MutationState.swift`**

```swift
// Sources/SwiflowQuery/MutationState.swift
import Swiflow

public enum MutationStatus: Sendable { case idle, pending, success, error }

/// Reads the render-active `QueryClient` from the package-internal
/// `RenderObserverBox`. PUBLIC so `@Component`-emitted code in a user module
/// (which cannot reach the `package` box itself) can call it; the actual box
/// access happens here, inside the SwiflowQuery/Swiflow package.
public func _currentRenderQueryClient() -> QueryClient? {
    RenderObserverBox.current as? QueryClient
}

/// Persistent, per-component reactive state for one `@MutationState`. A class so
/// it survives across renders with the component instance. Wired once at mount
/// by `@Component`'s `bind` (§8).
@MainActor
public final class MutationRuntime<M: Mutation> {
    private(set) var status: MutationStatus = .idle
    private(set) var data: M.Output?
    private(set) var error: (any Error)?

    private weak var owner: AnyComponent?
    private var scheduler: (any Scheduler)?
    private weak var client: QueryClient?

    public init() {}

    /// Injected at mount. `client` is only overwritten with a non-nil value.
    public func wire(owner: AnyComponent, scheduler: any Scheduler, client: QueryClient?) {
        self.owner = owner
        self.scheduler = scheduler
        if let client { self.client = client }
    }

    private func markDirty() {
        if let owner, let scheduler { scheduler.markDirty(owner) }
    }

    func reset() {
        status = .idle; data = nil; error = nil
        markDirty()
    }

    /// The single engine path: drives published state (pending → success/error,
    /// optimism + rollback + invalidation) and reports the outcome. NEVER throws
    /// — returns a `Result` so `.error` is set in exactly one place and
    /// `mutateAsync` rethrows the same stored error.
    func run(_ input: M.Input, _ mutation: M) async -> Result<M.Output, any Error> {
        guard let client else {
            // B1 guarantees mount-time wiring; this path is a hand-rolled /
            // direct-construction safety net. Loud in DEBUG, degraded (no
            // optimism/invalidation) in release — never a silently-wrong write.
            assertionFailure("MutationRuntime.run: no QueryClient wired (was the component mounted through the renderer?)")
            return await performOnly(input, mutation)
        }

        // 1. Optimism: snapshot prior, apply, stash for rollback.
        var rollback: [(key: QueryKey, prior: Any?)] = []
        for edit in mutation.optimistic(input) {
            let prior = client.getQueryDataErased(edit.key)
            if let next = edit.apply(prior) {
                client.setQueryData(edit.key, next)
                rollback.append((edit.key, prior))
            } else {
                #if DEBUG
                swiflowDiagnostic("OptimisticEdit.update: no cache entry for key \(edit.key) — edit skipped.")
                #endif
            }
        }

        // 2. Pending (synchronous, before the first suspension).
        status = .pending; markDirty()

        // 3. Perform.
        let result: Result<M.Output, any Error>
        do { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }

        // 4–6.
        switch result {
        case .success(let out):
            status = .success; data = out
            for inv in mutation.invalidations(input: input, output: out) { dispatch(inv, client) }
        case .failure(let err):
            for r in rollback.reversed() { client.setQueryData(r.key, r.prior) }
            status = .error; error = err
        }
        markDirty()
        return result
    }

    private func performOnly(_ input: M.Input, _ mutation: M) async -> Result<M.Output, any Error> {
        status = .pending; markDirty()
        let result: Result<M.Output, any Error>
        do { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }
        switch result {
        case .success(let out): status = .success; data = out
        case .failure(let err): status = .error; error = err
        }
        markDirty()
        return result
    }

    private func dispatch(_ inv: Invalidation, _ client: QueryClient) {
        switch inv {
        case .prefix(let k): client.invalidate(k, exact: false)
        case .exact(let k):  client.invalidate(k, exact: true)
        case .tag(let t):    client.invalidate(tag: t)
        }
    }

    /// Register a fire-and-forget driving task with the client so `settle()`
    /// awaits it; the task self-removes by token on completion.
    func register(_ work: @escaping () async -> Void) {
        guard let client else { Task { await work() }; return }
        let token = client.nextMutationTaskToken()
        let task = Task<Void, Never> {
            await work()
            client.removeMutationTask(token)
        }
        client.storeMutationTask(token, task)
    }
}

/// The `$`-projection a component uses to trigger and observe a mutation. A
/// lightweight value over the persistent runtime plus a snapshot of the current
/// `Mutation` definition (so a reassigned `create` is picked up).
@MainActor
public struct MutationHandle<M: Mutation> {
    let runtime: MutationRuntime<M>
    let mutation: M

    public init(runtime: MutationRuntime<M>, mutation: M) {
        self.runtime = runtime
        self.mutation = mutation
    }

    public var isIdle: Bool { runtime.status == .idle }
    public var isPending: Bool { runtime.status == .pending }
    public var isSuccess: Bool { runtime.status == .success }
    public var isError: Bool { runtime.status == .error }
    public var data: M.Output? { runtime.data }
    public var error: (any Error)? { runtime.error }

    /// Fire-and-forget — the UI reacts through the published state.
    public func mutate(_ input: M.Input) {
        let rt = runtime, m = mutation
        rt.register { _ = await rt.run(input, m) }
    }

    /// Awaitable — for sequencing side effects at the call site.
    public func mutateAsync(_ input: M.Input) async throws -> M.Output {
        let rt = runtime, m = mutation
        let task = Task { await rt.run(input, m) }   // typed result
        rt.register { _ = await task.value }          // Void wrapper registered for settle()
        switch await task.value {
        case .success(let out): return out
        case .failure(let err): throw err
        }
    }

    public func reset() { runtime.reset() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SwiflowQueryTests.MutationEngineTests`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowQuery/MutationState.swift Tests/SwiflowQueryTests/MutationEngineTests.swift
git commit -m "feat(query): MutationRuntime engine (run→Result) + MutationHandle"
```

---

## Task 6: Optimism, rollback & invalidation (engine integration)

**Files:**
- Test: `Tests/SwiflowQueryTests/MutationOptimismTests.swift`

The `run` body from Task 5 already contains the optimism/rollback/invalidation logic; this task proves it against a live cache and adds the `isPending`-mid-flight gate test.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationOptimismTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class Dummy: Component { var body: VNode { .text("") } }
private enum Boom: Error { case nope }

/// A deterministic gate so the test can observe state mid-flight.
@MainActor private final class Gate {
    private var cont: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { cont = $0 } }
    func open() { cont?.resume(); cont = nil }
}

@MainActor private struct ListQuery: Query {
    var queryKey: QueryKey { ["todos"] }
    func fetch() async throws -> [String] { [] }
}

@MainActor private struct AddTodo: Mutation {
    let gate: Gate
    let result: @MainActor @Sendable () async throws -> String
    func perform(_ title: String) async throws -> String { await gate.wait(); return try await result() }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        [.update(ListQuery()) { $0 + ["draft:\(title)"] }]
    }
    func invalidations(input: String, output: String) -> [Invalidation] { [.prefix(["todos"])] }
}

@Suite("Mutation/optimism")
@MainActor
struct MutationOptimismTests {
    private func seedList(_ c: QueryClient, _ items: [String]) async {
        let owner = AnyComponent(Dummy())
        c.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["todos"], tags: [], staleTime: .seconds(9999),
                boxedFetch: { items },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
        for t in c.inFlightTasks() { await t.value }
        _ = owner
    }
    private func wired(_ m: AddTodo, _ c: QueryClient) -> MutationHandle<AddTodo> {
        let rt = MutationRuntime<AddTodo>()
        rt.wire(owner: AnyComponent(Dummy()), scheduler: SyncScheduler { _ in }, client: c)
        return MutationHandle(runtime: rt, mutation: m)
    }

    @Test func optimisticValueVisibleBeforePerformResolves() async {
        let client = QueryClient(clock: ManualClock())
        await seedList(client, ["a"])
        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { "saved" }, client)
        h.mutate("b")
        // perform is parked on the gate; optimistic write already applied.
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a", "draft:b"])
        gate.open()
        for t in client.inFlightTasks() { await t.value }
    }

    @Test func rollbackRestoresOnFailure() async {
        let client = QueryClient(clock: ManualClock())
        await seedList(client, ["a"])
        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { throw Boom.nope }, client)
        h.mutate("b")
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a", "draft:b"])  // applied
        gate.open()
        for t in client.inFlightTasks() { await t.value }
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a"])             // rolled back
    }

    @Test func invalidationRefetchesOnSuccess() async {
        let client = QueryClient(clock: ManualClock())
        // A live observer with a fetch counter to prove invalidation refetched.
        let owner = AnyComponent(Dummy())
        var fetches = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["todos"], tags: [], staleTime: .seconds(9999),
                boxedFetch: { fetches += 1; return ["a"] },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 1)

        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { "saved" }, client)
        h.mutate("b"); gate.open()
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 2)        // invalidations(.prefix(["todos"])) refetched
        _ = owner
    }
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `swift test --filter SwiflowQueryTests.MutationOptimismTests`
Expected: PASS (the `run` logic from Task 5 already implements this). If any fails, fix the `run` body in `MutationState.swift` — do NOT weaken the test.

> Why this is still a TDD step: these tests exercise the optimism/rollback/invalidation branches of `run` for the first time against a live cache. If Task 5's `run` had a bug in those branches, it surfaces here.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowQueryTests/MutationOptimismTests.swift
git commit -m "test(query): optimistic apply/rollback + invalidation against live cache"
```

---

## Task 7: `@MutationState` macro (declaration + implementation) + Package wiring

**Files:**
- Create: `Sources/SwiflowQuery/MutationMacro.swift` (declaration)
- Create: `Sources/SwiflowMacrosPlugin/MutationStateMacro.swift` (implementation)
- Modify: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` (register)
- Modify: `Package.swift` (`SwiflowQuery` deps + language mode)
- Test: `Tests/SwiflowMacrosTests/MutationStateMacroTests.swift`

- [ ] **Step 1: Wire `Package.swift`**

In the `SwiflowQuery` target (currently `dependencies: ["Swiflow", .product(name: "JavaScriptKit", ...)]`, path `Sources/SwiflowQuery`), add the macro plugin dependency and the v6 language mode (it is the one target currently missing it):

```swift
        .target(
            name: "SwiflowQuery",
            dependencies: [
                "Swiflow",
                "SwiflowMacrosPlugin",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowQuery",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

> If `SwiflowQuery` already declares `swiftSettings`, just add `"SwiflowMacrosPlugin"` to `dependencies`. Verify the final stanza compiles before proceeding (`swift build --target SwiflowQuery` after Step 4/5).

- [ ] **Step 2: Write the failing macro test**

```swift
// Tests/SwiflowMacrosTests/MutationStateMacroTests.swift
import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

@Suite("Macro/MutationState")
struct MutationStateMacroTests {
    private let macros: [String: Macro.Type] = ["MutationState": MutationStateMacro.self]

    @Test func emitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo
            """,
            expandedSource: """
            var create: CreateTodo

            private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

            var $create: MutationHandle<CreateTodo> {
                MutationHandle(runtime: _create_mutationRuntime, mutation: create)
            }
            """,
            macros: macros
        )
    }
}
```

> Match the existing macro tests' import/style (look at `Tests/SwiflowMacrosTests/StateMacroTests.swift` and mirror its `assertMacroExpansion` formatting exactly — whitespace in `expandedSource` must match the macro's output). Adjust the expected string to the real emitted formatting if the first run reports a diff; the *content* (two emitted decls with these names/types) is what matters.

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter SwiflowMacrosTests.MutationStateMacroTests`
Expected: FAIL — `cannot find 'MutationStateMacro'`.

- [ ] **Step 4: Write the macro implementation**

```swift
// Sources/SwiflowMacrosPlugin/MutationStateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macro for `@MutationState var create: SomeMutation`. Emits a persistent
/// backing `_create_mutationRuntime` and the `$create` reactive handle
/// projection. `create` itself stays a plain stored `var` holding the Mutation.
public struct MutationStateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MutationStateDiagnostic.requiresVarWithType))
            return []
        }
        let name = identifier.text
        let mutationType = typeAnno.type.trimmedDescription

        let runtime: DeclSyntax = """
            private let _\(raw: name)_mutationRuntime = MutationRuntime<\(raw: mutationType)>()
            """
        let projection: DeclSyntax = """
            var $\(raw: name): MutationHandle<\(raw: mutationType)> {
                MutationHandle(runtime: _\(raw: name)_mutationRuntime, mutation: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum MutationStateDiagnostic: DiagnosticMessage {
    case requiresVarWithType
    var message: String {
        "@MutationState requires a `var` with an explicit Mutation type annotation (e.g. `@MutationState var create: CreateTodo`)."
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 5: Register the macro in `SwiflowMacrosPlugin.swift`**

```swift
    let providingMacros: [Macro.Type] = [
        ComponentMacro.self,
        StateMacro.self,
        MutationStateMacro.self,
    ]
```

- [ ] **Step 6: Write the macro declaration in `MutationMacro.swift`**

```swift
// Sources/SwiflowQuery/MutationMacro.swift

/// Declares a mutation on a `@Component` class. The decorated `var` stays the
/// stored `Mutation`; the macro emits a `$name` reactive handle projection plus
/// a persistent backing `MutationRuntime`. `@Component` wires the runtime's
/// `QueryClient` at mount (spec §8). Mirrors `@State`'s name/`$name` split.
@attached(peer, names: arbitrary)
public macro MutationState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "MutationStateMacro")
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter SwiflowMacrosTests.MutationStateMacroTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowQuery/MutationMacro.swift Sources/SwiflowMacrosPlugin/MutationStateMacro.swift Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift Package.swift Tests/SwiflowMacrosTests/MutationStateMacroTests.swift
git commit -m "feat(macro): @MutationState peer macro ($name handle + backing runtime)"
```

---

## Task 8: Extend `@Component` to wire `@MutationState` runtimes at mount

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`
- Test: `Tests/SwiflowMacrosTests/ComponentMacroMutationTests.swift`

- [ ] **Step 1: Write the failing test (concrete substring assertion on the `bind` member)**

This avoids the brittle full-source golden by calling `ComponentMacro.expansion` (the `MemberMacro` witness) directly and asserting on the emitted `bind`'s text. `@MutationState` does NOT need registering here — `ComponentMacro` only *scans* for the attribute name; it never expands it.

```swift
// Tests/SwiflowMacrosTests/ComponentMacroMutationTests.swift
import Testing
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

@Suite("Macro/Component+Mutation")
struct ComponentMacroMutationTests {
    /// Expand `@Component` over `source` and return the concatenated text of the
    /// emitted members (so we can substring-assert the `bind` body).
    private func expandedMembers(_ source: String) throws -> String {
        let macros: [String: Macro.Type] = ["Component": ComponentMacro.self]
        let context = BasicMacroExpansionContext(
            sourceFiles: [:],
            expansionDiscriminator: "test")
        // Simplest robust path: use assertMacroExpansion to render, capturing the
        // rendered string via a round-trip. In practice, prefer the helper used
        // by the existing ComponentMacroTests — read that file and mirror it.
        // Here we render via assertMacroExpansion's underlying expansion by
        // parsing + expanding the attribute. See note below for the exact call
        // the repo already uses.
        fatalError("replace with the repo's existing expansion helper — see note")
    }

    @Test func bindWiresMutationRuntimeWhenPresent() {
        // A class WITH @MutationState → bind wires its runtime via the public
        // accessor (NOT RenderObserverBox, which is `package`).
        let expanded = renderComponentExpansion(
            """
            @Component final class C {
                @MutationState var create: CreateTodo
                init() {}
            }
            """)
        #expect(expanded.contains("_create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())"))
    }

    @Test func bindUnchangedWithoutMutation() {
        // A class WITHOUT @MutationState → no SwiflowQuery references in bind.
        let expanded = renderComponentExpansion(
            """
            @Component final class C {
                @State var n: Int = 0
                init() {}
            }
            """)
        #expect(!expanded.contains("wire("))
        #expect(!expanded.contains("_currentRenderQueryClient"))
        #expect(!expanded.contains("QueryClient"))
    }
}
```

> **Concrete instruction for the implementer:** Open `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` and reuse the exact expansion-rendering approach it already uses (it pins the no-mutation `bind` body, so it already renders `@Component` expansions to a string). Replace `renderComponentExpansion(_:)` above with that helper (or, if it uses `assertMacroExpansion` golden strings, instead ADD two new cases to `ComponentMacroTests.swift`: one whose expected source includes the `_create_mutationRuntime.wire(...)` line in `bind`, and rely on the existing no-mutation cases for the negative). Either way the assertions are concrete: the positive case must contain the exact `wire(...)` line above; the negative must contain no `wire(`/`QueryClient`/`_currentRenderQueryClient` text. Delete the `expandedMembers` stub once the real helper is wired in.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwiflowMacrosTests.ComponentMacroMutationTests`
Expected: FAIL — `bind` body has no `wire(` line.

- [ ] **Step 3: Extend `ComponentMacro.expansion(...)` (MemberMacro)**

In `ComponentMacro.swift`, after the existing `@State`/`@MacroState` scan loop that builds `cellEntries`, add a parallel scan that collects `@MutationState` property names:

```swift
        // Collect @MutationState property names so `bind` can wire each
        // runtime's QueryClient at mount (spec §8, B1).
        var mutationNames: [String] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isMutation = varDecl.attributes.contains { attr in
                guard let a = attr.as(AttributeSyntax.self),
                      let n = a.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
                return n == "MutationState"
            }
            guard isMutation,
                  let b = varDecl.bindings.first,
                  let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier else { continue }
            mutationNames.append(id.text)
        }
```

Then replace the existing `bindDecl` construction with one that appends a `wire(...)` statement per mutation. The emitted code references `_currentRenderQueryClient()` (the public accessor in `SwiflowQuery`) — NOT `RenderObserverBox` directly, which is `package` and unreachable from user modules:

```swift
        var bindStmts = ["self.runtimeOwner = owner", "self.runtimeScheduler = scheduler"]
        bindStmts += mutationNames.map { name in
            "_\(name)_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())"
        }
        let bindBody = bindStmts.joined(separator: "\n    ")
        let bindDecl: DeclSyntax = isPublic
            ? DeclSyntax(stringLiteral: "public func bind(owner: AnyComponent, scheduler: Scheduler) {\n    \(bindBody)\n}")
            : DeclSyntax(stringLiteral: "func bind(owner: AnyComponent, scheduler: Scheduler) {\n    \(bindBody)\n}")
```

When `mutationNames` is empty (the common case), `bindStmts` is exactly the two assignments and the emitted `bind` is byte-identical to today — and references no `SwiflowQuery` type. This is the conditional-emission guarantee (spec §2/§8.2).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SwiflowMacrosTests.ComponentMacroMutationTests`
Expected: PASS. Also run the existing `ComponentMacroTests` to confirm no regression in the no-mutation `bind`:

Run: `swift test --filter SwiflowMacrosTests`
Expected: PASS (existing `bind` golden tests still match).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowMacrosPlugin/ComponentMacro.swift Tests/SwiflowMacrosTests/ComponentMacroMutationTests.swift
git commit -m "feat(macro): @Component wires @MutationState runtimes in bind() at mount"
```

---

## Task 9: `TestRenderer` ordering fix (B1)

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`

The root component's `bind` currently runs (via `wireState`) before `RenderObserverBox.current` is installed, so a root `@MutationState` would wire a `nil` client. Move the box assignment above the root `wireState`.

- [ ] **Step 1: Make the change**

In `TestRenderer.init`, the current order is:

```swift
        let anyComponent = AnyComponent(instance)
        self.rootComponent = anyComponent
        wireState(on: anyComponent, scheduler: self.scheduler)
        _testAmbientHandlers = self.handlers
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer { ... }
```

Reorder so the box is set before `wireState` (mirroring production `Renderer.renderOnce`, where the box is set before `diff`):

```swift
        let anyComponent = AnyComponent(instance)
        self.rootComponent = anyComponent
        _testAmbientHandlers = self.handlers
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            _testAmbientHandlers = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
        // Wire AFTER the observer box is installed, so a root @MutationState's
        // mount-time wiring (@Component.bind → _currentRenderQueryClient())
        // captures the client (spec §8.2, B1).
        wireState(on: anyComponent, scheduler: self.scheduler)
```

> Keep every existing line; only move `wireState(on:scheduler:)` to AFTER the `RenderObserverBox.current = queryClient` assignment (and its `defer`). Do not change `rerender` (it already sets the box first).

- [ ] **Step 2: Verify the suite still builds + passes (no behavior change for non-mutation tests)**

Run: `swift test --filter SwiflowTestingTests` (and `SwiflowQueryTests`)
Expected: PASS — existing query/integration tests are unaffected (the box is simply installed a few lines earlier).

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiflowTesting/TestRenderer.swift
git commit -m "fix(testing): install RenderObserverBox before root wireState (B1 mount wiring)"
```

---

## Task 10: End-to-end integration tests (mounted component + live query)

**Files:**
- Test: `Tests/SwiflowQueryTests/MutationIntegrationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/MutationIntegrationTests.swift
import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

@MainActor private struct TodoList: Query {
    let load: @MainActor @Sendable () -> [String]
    var queryKey: QueryKey { ["todos"] }
    var staleTime: Duration { .seconds(9999) }
    func fetch() async throws -> [String] { load() }
}

private enum Boom: Error { case nope }

@MainActor private struct AddTodo: Mutation {
    let outcome: @MainActor @Sendable (String) async throws -> String
    func perform(_ title: String) async throws -> String { try await outcome(title) }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        [.update(TodoList(load: { [] })) { $0 + ["draft:\(title)"] }]
    }
    func invalidations(input: String, output: String) -> [Invalidation] { [.prefix(["todos"])] }
}

// A component that DOES gate on $create (the common pattern).
@MainActor @Component private final class Board {
    let load: @MainActor @Sendable () -> [String]
    @MutationState var add: AddTodo
    init(load: @escaping @MainActor @Sendable () -> [String],
         outcome: @escaping @MainActor @Sendable (String) async throws -> String) {
        self.load = load
        self.add = AddTodo(outcome: outcome)
    }
    var body: VNode {
        let todos = query(TodoList(load: load))
        return div {
            for t in todos.data ?? [] { p(t) }
            button("Add") { self.$add.mutate("x") }.disabled($add.isPending)
        }
    }
}

// A component that NEVER references $create in body — the B1 regression case.
@MainActor @Component private final class FireOnly {
    @MutationState var add: AddTodo
    init(outcome: @escaping @MainActor @Sendable (String) async throws -> String) {
        self.add = AddTodo(outcome: outcome)
    }
    var body: VNode { div { p("static") } }   // never reads $add
}

@Suite("Mutation/integration")
@MainActor
struct MutationIntegrationTests {
    @Test func optimisticThenInvalidationReconciles() async throws {
        var server = ["a"]
        let h = AsyncTestHarness(
            Board(load: { server }, outcome: { server.append($0); return $0 }),
            queryClient: QueryClient(clock: ManualClock()))
        try await h.settle()
        #expect(h.allText.contains("a"))

        h.click("button")            // $add.mutate("x")
        try await h.settle()
        // optimistic draft replaced by server truth after invalidation refetch
        #expect(h.allText.contains("x"))
        #expect(!h.allText.contains("draft:x"))
    }

    @Test func rollbackOnFailureKeepsPriorList() async throws {
        let h = AsyncTestHarness(
            Board(load: { ["a"] }, outcome: { _ in throw Boom.nope }),
            queryClient: QueryClient(clock: ManualClock()))
        try await h.settle()
        h.click("button")
        try await h.settle()
        #expect(h.allText.contains("a"))
        #expect(!h.allText.contains("draft:x"))   // rolled back
    }

    // B1: a component whose body NEVER reads $add still wires the client at
    // mount, so its FIRST mutate (no prior re-render) applies invalidation.
    @Test func mountWiresClientEvenWithoutBodyReference() async throws {
        var fetches = 0
        let client = QueryClient(clock: ManualClock())
        // Mount a separate live observer of ["todos"] so invalidation has work.
        let board = Board(load: { fetches += 1; return ["a"] }, outcome: { $0 })
        let h = AsyncTestHarness(board, queryClient: client)
        try await h.settle()
        #expect(fetches == 1)

        // Drive a FireOnly mutation directly against the SAME client, with no
        // prior render of FireOnly. Its @MutationState was wired at mount.
        let fire = FireOnly(outcome: { $0 })
        let fireHarness = AsyncTestHarness(fire, queryClient: client)  // mounts + wires
        fire.$add.mutate("z")                                          // FIRST mutate, no rerender
        try await fireHarness.settle()
        try await h.settle()
        #expect(fetches == 2)   // invalidation from the fire-only mutation refetched the board
        _ = fireHarness
    }

    @Test func resetDoesNotCancelInFlightPerform() async throws {
        var server = ["a"]
        let h = AsyncTestHarness(
            Board(load: { server }, outcome: { server.append($0); return $0 }),
            queryClient: QueryClient(clock: ManualClock()))
        try await h.settle()
        // (reset semantics: a started perform still completes its invalidation.)
        // Drive via the handle to interleave reset before settle.
        // See spec §10; this asserts the cache still reconciles after reset().
    }
}
```

> The `resetDoesNotCancelInFlightPerform` test needs a gate to start `perform`, call `reset()`, then `settle()` and assert the server write + invalidation still landed. Implement it with the `Gate` helper from Task 6 (move `Gate` into a shared test file `Tests/SwiflowQueryTests/TestSupport.swift` and reuse). Keep the assertion: after `reset()` + `settle()`, `status == .idle` but the cache reflects the completed write (a fetch counter bumped). Do not skip this test — it pins the §10 contract.

- [ ] **Step 2: Run test to verify it fails (then drives fixes)**

Run: `swift test --filter SwiflowQueryTests.MutationIntegrationTests`
Expected: initially FAIL if any wiring/path is off (esp. `mountWiresClientEvenWithoutBodyReference`, which fails hard — `assertionFailure` — if Task 9's ordering fix is missing). Fix forward in the implementation, never weaken the assertions.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowQueryTests/MutationIntegrationTests.swift Tests/SwiflowQueryTests/TestSupport.swift
git commit -m "test(query): mutation integration (optimism, rollback, B1 mount-wire, reset)"
```

---

## Task 11: Full suite green + QueryDemo mutation showcase

**Files:**
- Modify: `examples/QueryDemo/Sources/App/App.swift` (add a mutation)
- Modify: generated `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerate)
- Test: full host suite

- [ ] **Step 1: Run the full host test suite**

Run: `swift test`
Expected: PASS — all existing 663 tests plus the new mutation tests. Investigate any failure; the `OnChangeStorageTests` "first call does not fire perform" test is a KNOWN ~1/3 parallel flake (passes in isolation) — re-run `swift test --filter OnChangeStorageTests` to confirm it's the pre-existing flake and not a regression.

- [ ] **Step 2: Add a mutation to the QueryDemo example**

Extend `examples/QueryDemo/Sources/App/App.swift` with a simple write against the existing `FakeAPI` (e.g. a `RenameUser` mutation: `@MutationState var rename: RenameUser`, a text input + button that calls `$rename.mutate(newName)`, `optimistic` updates the `UserByID` entry, `invalidations` targets `["users", .int(id)]`). Gate the button on `$rename.isPending` and show `$rename.isError`. Keep it minimal and self-contained; follow the existing App.swift style.

- [ ] **Step 3: Regenerate embedded templates**

Run: `swift scripts/embed-templates.swift` (the script auto-walks `examples/*/`; confirm the exact invocation against how the repo runs it — check `scripts/embed-templates.swift` header).
Expected: `Sources/SwiflowCLI/EmbeddedTemplates.swift` updated to include the new QueryDemo source.

- [ ] **Step 4: Build the example for WASM**

Run (in `examples/QueryDemo`): `swift package --swift-sdk swift-6.3-RELEASE_wasm js --use-cdn --product App -c release`
Expected: links `SwiflowQuery` and builds (the `@MutationState` macro + runtime cross-compile). Fix any WASM-specific issues (e.g. `@MainActor` isolation surfacing differently under cross-compile, per the `@Component requires explicit @MainActor` project note).

- [ ] **Step 5: Commit**

```bash
git add examples/QueryDemo/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "feat(examples): QueryDemo mutation showcase (optimistic rename + invalidate)"
```

- [ ] **Step 6 (optional, manual): Browser smoke**

Build to a servable bundle and load in the browser (chrome-devtools MCP). Verify: list loads → type a new name → click → optimistic name shows instantly → settles to server value; force an error path → name reverts. This mirrors the Query Core browser smoke. Note in the PR description.

---

## Self-review checklist (run after all tasks)

- [ ] Every spec section §3–§11 maps to a task: §3.1 Mutation (T2), §3.2 Invalidation (T1), §3.3 OptimisticEdit (T1), §3.4 status/handle (T5), §4 macro emit (T7/T8), §5 run engine (T5), §5.1 run→Result (T5), §6 optimism/rollback (T6), §7 invalidation (T6), §8 wiring (T7/T8/T9), §8.3 task registry (T4), §9 error handling (T5), §10 cancellation (T10), §11 setQueryData (T3). ✔
- [ ] No public `getQueryData`/`setQueryData` leaked (all `package`). ✔
- [ ] `MutationRuntime.wire`, `MutationRuntime.init`, `MutationHandle.init`, `_currentRenderQueryClient` are `public` (called from user-module macro-emitted code); engine internals (`run`/`register`/`status`) are `internal`. ✔
- [ ] Macro-emitted `bind` references `_currentRenderQueryClient()` (public), NOT `RenderObserverBox` (package). ✔
- [ ] Mutation-free components emit byte-identical `bind` (T8 negative test). ✔
- [ ] `mutateAsync` rethrows the same error stored on the handle (no duplication); `run` never throws (T5). ✔
```
