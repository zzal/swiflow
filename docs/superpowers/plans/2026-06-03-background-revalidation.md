# Background Revalidation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add background revalidation to `SwiflowQuery` — refetch-on-window-focus, polling (`refetchInterval`), and retry/backoff — driven by a clock-based `tick`, reusing the existing `Clock`/`ManualClock` so it stays deterministic.

**Architecture:** Per-query config lives as defaulted members on the self-describing `Query` protocol; per-entry state lives on `QueryEntry`. Two `package` `QueryClient` entry points — `tick(now:)` (poll + retry) and `focusChanged(visible:)` (stale-only, dedup-safe) — are driven by one always-on JS `setInterval` + `visibilitychange`/`focus` listener in SwiflowWeb (production) and by `AsyncTestHarness.advance(by:)`/`focus()` (tests). Retry threads through the existing `commitFetch`; the existing generation guard + `inFlight` dedup keep background refetches safe.

**Tech Stack:** Swift 6, WebAssembly (`wasm32`), JavaScriptKit (WASM-only JS, behind `#if canImport(JavaScriptKit)`), swift-testing.

**Spec:** `docs/superpowers/specs/2026-06-03-background-revalidation-design.md` (rev 2 + confirmation pass).

**Conventions for the implementer:**
- Verify with `swift test --filter <suite>` (host) and, where noted, `.build/debug/swiflow build --path examples/TodoCRUD` (WASM cross-compile). SourceKit "No such module" diagnostics in this repo are **stale** — trust `swift build`/`swift test`.
- Tests use `@testable import SwiflowQuery` + `import Swiflow`.
- `tick`/`focusChanged` are `package` (same-package callers: SwiflowWeb wiring + the test harness), like `inFlightTasks()`.

---

## File Structure

**New:**
- `Sources/SwiflowQuery/RetryPolicy.swift` — the retry value type + backoff.
- `Sources/SwiflowWeb/BackgroundRevalidation.swift` — WASM-only JS wiring (interval + focus listener).
- `Tests/SwiflowQueryTests/RetryPolicyTests.swift`
- `Tests/SwiflowQueryTests/BackgroundSupport.swift` — shared test scaffold (controllable fetch + client + advance/focus).
- `Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift` — poll / retry / focus / supersede tests.

**Modified:**
- `Sources/SwiflowQuery/Query.swift` — `refetchInterval`/`refetchOnFocus`/`retry` protocol members + defaults.
- `Sources/SwiflowQuery/QueryEntry.swift` — `staleTime` + background/retry state.
- `Sources/SwiflowQuery/QueryClient.swift` — `QueryObservation` fields, `observe`/`reconcile` copy, `tick(now:)`, `focusChanged(visible:)`, `commitFetch` retry, `forceStaleAndRefetch` retry-reset, `backoff` via `RetryPolicy`.
- `Sources/SwiflowQuery/QueryClient+Cache.swift` — `setQueryData` retry-reset.
- `Sources/SwiflowTesting/AsyncTestHarness.swift` — own a `ManualClock`; `advance(by:)` + `focus()`.
- `examples/TodoCRUD/Sources/App/App.swift` — `refetchInterval` showcase.
- `Sources/SwiflowCLI/EmbeddedTemplates.swift` — regenerated (TodoCRUD changed).

---

## Task 1: `RetryPolicy`

**Files:**
- Create: `Sources/SwiflowQuery/RetryPolicy.swift`
- Test: `Tests/SwiflowQueryTests/RetryPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/RetryPolicyTests.swift
import Testing
@testable import SwiflowQuery

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test func defaultBackoffSequence() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 0) == .seconds(1))
        #expect(p.delay(forAttempt: 1) == .seconds(2))
        #expect(p.delay(forAttempt: 2) == .seconds(4))
    }
    @Test func backoffCapsAndNeverOverflows() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 5) == .seconds(30))      // 1·2^5 = 32s → capped at 30s
        #expect(p.delay(forAttempt: 100_000) == .seconds(30))// no Duration overflow/trap
    }
    @Test func noneDisablesRetry() {
        #expect(RetryPolicy.none.maxRetries == 0)
    }
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter RetryPolicy` → FAIL ("cannot find 'RetryPolicy'").

- [ ] **Step 3: Implement**

```swift
// Sources/SwiflowQuery/RetryPolicy.swift

/// How a failed query fetch is retried. A closure-free value (`Sendable` +
/// `Equatable`) so it can live on the `Query` protocol.
public struct RetryPolicy: Sendable, Equatable {
    /// Retries AFTER the initial fetch (total attempts = `maxRetries + 1`).
    public var maxRetries: Int
    /// Delay before the first retry; doubles each retry, capped at `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxRetries: Int, baseDelay: Duration, maxDelay: Duration) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// No retries.
    public static let none = RetryPolicy(maxRetries: 0, baseDelay: .zero, maxDelay: .zero)
    /// 3 retries at 1s / 2s / 4s, capped at 30s.
    public static let `default` = RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))

    /// Backoff before retry `n` (0-indexed) = `baseDelay × 2ⁿ`, capped at `maxDelay`.
    /// Clamps the RESULT by doubling, so it never forms an overflowing product.
    func delay(forAttempt n: Int) -> Duration {
        var d = baseDelay
        if d >= maxDelay { return maxDelay }
        for _ in 0..<n {
            d = d * 2
            if d >= maxDelay { return maxDelay }
        }
        return d
    }
}
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter RetryPolicy` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/RetryPolicy.swift Tests/SwiflowQueryTests/RetryPolicyTests.swift
git commit -m "feat(query): add RetryPolicy with result-clamped exponential backoff"
```

---

## Task 2: `Query` protocol — background config members

**Files:**
- Modify: `Sources/SwiflowQuery/Query.swift`
- Test: `Tests/SwiflowQueryTests/QueryProtocolTests.swift` (append)

- [ ] **Step 1: Write the failing test** (append to the existing `QueryProtocolTests` suite)

```swift
// Tests/SwiflowQueryTests/QueryProtocolTests.swift  (add inside the @Suite struct)
@MainActor private struct PlainQ: Query {
    var queryKey: QueryKey { ["p"] }
    func fetch() async throws -> Int { 0 }
}
@MainActor private struct TunedQ: Query {
    var queryKey: QueryKey { ["t"] }
    var refetchInterval: Duration? { .seconds(5) }
    var refetchOnFocus: Bool { false }
    var retry: RetryPolicy { .none }
    func fetch() async throws -> Int { 0 }
}

@Test func backgroundConfigDefaults() {
    let p = PlainQ()
    #expect(p.refetchInterval == nil)
    #expect(p.refetchOnFocus == true)
    #expect(p.retry == .default)
}
@Test func backgroundConfigOverrides() {
    let t = TunedQ()
    #expect(t.refetchInterval == .seconds(5))
    #expect(t.refetchOnFocus == false)
    #expect(t.retry == .none)
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter QueryProtocol` → FAIL ("value of type 'PlainQ' has no member 'refetchInterval'").

- [ ] **Step 3: Implement** — in `Sources/SwiflowQuery/Query.swift`, add the three members to the protocol (after `staleTime`, before `fetch`) and to the extension:

```swift
    /// Polling cadence. `nil` (default) = no polling.
    var refetchInterval: Duration? { get }

    /// Whether this query refetches (if stale) when the window regains focus.
    /// Defaults to `true`.
    var refetchOnFocus: Bool { get }

    /// Retry policy for failed fetches. Defaults to `.default`.
    var retry: RetryPolicy { get }
```
```swift
public extension Query {
    var tags: Set<QueryTag> { [] }
    var staleTime: Duration { .zero }
    var refetchInterval: Duration? { nil }
    var refetchOnFocus: Bool { true }
    var retry: RetryPolicy { .default }
}
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter QueryProtocol` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/Query.swift Tests/SwiflowQueryTests/QueryProtocolTests.swift
git commit -m "feat(query): add refetchInterval/refetchOnFocus/retry to Query protocol"
```

---

## Task 3: `QueryEntry` — background + retry state

**Files:**
- Modify: `Sources/SwiflowQuery/QueryEntry.swift`
- Test: `Tests/SwiflowQueryTests/QueryEntryTests.swift` (append)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/QueryEntryTests.swift  (add inside the @Suite struct)
@Test func backgroundStateDefaults() {
    let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
    #expect(e.staleTime == .zero)
    #expect(e.refetchInterval == nil)
    #expect(e.refetchOnFocus == true)
    #expect(e.retry == .default)
    #expect(e.failureCount == 0)
    #expect(e.nextRetryDue == nil)
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter QueryEntry` → FAIL ("has no member 'staleTime'").

- [ ] **Step 3: Implement** — add to `QueryEntry` (in `Sources/SwiflowQuery/QueryEntry.swift`), after the `tags` property:

```swift
    /// Promoted from the latest observation (needed off the render path, by
    /// `tick`/`focusChanged`). The defaults below apply until `reconcile` copies
    /// the query's values on; existing call sites that build an entry directly
    /// (tests) keep compiling.
    var staleTime: Duration = .zero
    var refetchInterval: Duration?
    var refetchOnFocus: Bool = true
    var retry: RetryPolicy = .default
    /// Consecutive fetch failures; reset to 0 on any success or supersede.
    var failureCount: Int = 0
    /// Clock time the next retry should fire; `nil` = no pending retry.
    var nextRetryDue: Duration?
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter QueryEntry` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryEntry.swift Tests/SwiflowQueryTests/QueryEntryTests.swift
git commit -m "feat(query): add background + retry state to QueryEntry"
```

---

## Task 4: `QueryObservation` fields + `observe`/`reconcile` copy

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (`QueryObservation` struct, `observe`, `reconcile`)
- Test: `Tests/SwiflowQueryTests/QueryClientReconcileTests.swift` (append)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowQueryTests/QueryClientReconcileTests.swift  (add inside the @Suite struct)
@MainActor private struct TunedQuery: Query {
    var queryKey: QueryKey { ["tuned"] }
    var staleTime: Duration { .seconds(7) }
    var refetchInterval: Duration? { .seconds(5) }
    var refetchOnFocus: Bool { false }
    var retry: RetryPolicy { .none }
    func fetch() async throws -> Int { 1 }
}

@Test func reconcileCopiesBackgroundConfigOntoEntry() async {
    let client = QueryClient(clock: ManualClock())
    let owner = AnyComponent(Dummy())
    client.willEvaluate(owner: owner, scheduler: SyncScheduler { _ in })
    _ = client.observe(TunedQuery())
    client.didEvaluate()
    for t in client.inFlightTasks() { await t.value }

    let entry = client.entries[["tuned"]]!
    #expect(entry.staleTime == .seconds(7))
    #expect(entry.refetchInterval == .seconds(5))
    #expect(entry.refetchOnFocus == false)
    #expect(entry.retry == .none)
    _ = owner
}
```
> Note: `QueryClientReconcileTests` already defines a `Dummy: Component`. If not present in the file you are editing, add: `@MainActor private final class Dummy: Component { var body: VNode { .text("") } }`.

- [ ] **Step 2: Run, expect fail** — `swift test --filter QueryClientReconcile` → FAIL (extra args to `QueryObservation` / missing entry fields are not copied).

- [ ] **Step 3: Implement** — three edits in `Sources/SwiflowQuery/QueryClient.swift`:

(a) Add fields to `QueryObservation`:
```swift
    struct QueryObservation {
        let key: QueryKey
        let tags: Set<QueryTag>
        let staleTime: Duration
        let refetchInterval: Duration?
        let refetchOnFocus: Bool
        let retry: RetryPolicy
        let boxedFetch: @MainActor () async throws -> Any
        let valuesEqual: (Any?, Any?) -> Bool
    }
```

(b) In `observe`, populate them from the query:
```swift
        let ob = QueryObservation(
            key: key,
            tags: q.tags,
            staleTime: q.staleTime,
            refetchInterval: q.refetchInterval,
            refetchOnFocus: q.refetchOnFocus,
            retry: q.retry,
            boxedFetch: { try await q.fetch() },
            valuesEqual: { ($0 as? Q.Value) == ($1 as? Q.Value) }
        )
```

(c) In `reconcile`, copy onto the entry where it already copies `tags`/`boxedFetch`:
```swift
            entry.tags = ob.tags
            entry.boxedFetch = ob.boxedFetch          // capture latest deps
            entry.staleTime = ob.staleTime
            entry.refetchInterval = ob.refetchInterval
            entry.refetchOnFocus = ob.refetchOnFocus
            entry.retry = ob.retry
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter QueryClientReconcile` → PASS. Then `swift build` to confirm no other `QueryObservation` construction site broke (the test-only ones are updated in Task 5).

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/QueryClientReconcileTests.swift
git commit -m "feat(query): carry background config through QueryObservation onto the entry"
```

---

## Task 5: `tick`/`focusChanged` stubs + shared test scaffold

Introduces the two `package` entry points (empty for now) and the reusable test harness used by Tasks 6–9.

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (add stubs)
- Create: `Tests/SwiflowQueryTests/BackgroundSupport.swift`

- [ ] **Step 1: Add the stubs** in `Sources/SwiflowQuery/QueryClient.swift` (in the `// MARK: - Freshness` area, after `needsFetch`):

```swift
    // MARK: - Background revalidation

    /// Driven by the production interval (and tests). Fires due retries and
    /// due polls for live, not-in-flight entries. Filled in by later tasks.
    package func tick(now: Duration) {
    }

    /// Driven by the production focus listener (and tests). Refetches stale,
    /// focus-enabled, live entries. Filled in by a later task.
    package func focusChanged(visible: Bool) {
    }
```

- [ ] **Step 2: Create the test scaffold**

```swift
// Tests/SwiflowQueryTests/BackgroundSupport.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor final class BGDummy: Component { var body: VNode { .text("") } }

/// A controllable fetch: counts calls; the next `failuresRemaining` calls throw.
@MainActor final class FetchProbe {
    var calls = 0
    var failuresRemaining = 0
    enum Boom: Error { case fail }
    func run() async throws -> [String] {
        calls += 1
        if failuresRemaining > 0 { failuresRemaining -= 1; throw Boom.fail }
        return ["v\(calls)"]
    }
}

/// One live query observation wired to a `ManualClock`, with helpers to drive
/// background triggers deterministically. Mirrors how `tick`/`focusChanged`
/// will be driven in production.
@MainActor final class BG {
    let clock = ManualClock()
    let client: QueryClient
    let owner = AnyComponent(BGDummy())
    let probe = FetchProbe()

    init(staleTime: Duration = .seconds(9999),
         refetchInterval: Duration? = nil,
         refetchOnFocus: Bool = true,
         retry: RetryPolicy = .none) {
        client = QueryClient(clock: clock)
        let probe = self.probe
        client.reconcile(
            owner: owner,
            scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["k"], tags: [], staleTime: staleTime,
                refetchInterval: refetchInterval, refetchOnFocus: refetchOnFocus, retry: retry,
                boxedFetch: { try await probe.run() },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
    }

    func settle() async { for t in client.inFlightTasks() { await t.value } }
    /// Advance the clock, tick, and drain resulting fetches.
    func advance(_ d: Duration) async { clock.advance(by: d); client.tick(now: clock.now()); await settle() }
    func focus() async { client.focusChanged(visible: true); await settle() }
    var entry: QueryEntry { client.entries[["k"]]! }
}
```

- [ ] **Step 3: Verify it compiles + the initial fetch ran** — add to `BackgroundRevalidationTests` (create the file with this first test):

```swift
// Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@Suite("Background/scaffold")
@MainActor
struct BackgroundScaffoldTests {
    @Test func initialReconcileFetchesOnce() async {
        let bg = BG()
        await bg.settle()
        #expect(bg.probe.calls == 1)            // mount triggered one fetch
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter Background` → PASS (and `swift build` clean: the stubs + scaffold compile).

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/BackgroundSupport.swift Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
git commit -m "feat(query): tick/focusChanged package stubs + background test scaffold"
```

---

## Task 6: `tick` — polling

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (`tick`)
- Test: `Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Background/polling")
@MainActor
struct BackgroundPollingTests {
    @Test func pollFiresAtInterval() async {
        let bg = BG(refetchInterval: .seconds(5))
        await bg.settle()
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(4))           // not yet due
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(1))           // now 5s since last fetch → poll
        #expect(bg.probe.calls == 2)
    }
    @Test func noPollWithoutInterval() async {
        let bg = BG()                            // refetchInterval nil
        await bg.settle()
        await bg.advance(.seconds(9999))
        #expect(bg.probe.calls == 1)
    }
    @Test func neverSucceededDoesNotPoll() async {
        let bg = BG(refetchInterval: .seconds(5))
        bg.probe.failuresRemaining = 1           // initial fetch fails → lastFetched stays nil
        await bg.settle()
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(5))            // poll branch requires lastFetched != nil
        // retry is .none here, so no retry either; poll must not fire
        #expect(bg.probe.calls == 1)
    }
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter Background/polling` → FAIL (`calls` stays 1; tick does nothing yet).

- [ ] **Step 3: Implement `tick`** in `Sources/SwiflowQuery/QueryClient.swift`:

```swift
    package func tick(now: Duration) {
        for (key, entry) in entries {
            guard hasLiveSubscribers(key), entry.inFlight == nil else { continue }
            if let due = entry.nextRetryDue, now >= due {
                entry.nextRetryDue = nil
                startFetch(for: key, entry: entry)          // retry (Task 7)
                continue
            }
            if let interval = entry.refetchInterval,
               let last = entry.lastFetched, now - last >= interval {
                startFetch(for: key, entry: entry)          // poll
            }
        }
    }
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter Background/polling` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
git commit -m "feat(query): clock-driven polling via tick(now:)"
```

---

## Task 7: Retry — `commitFetch` scheduling + `tick` retry branch

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (`commitFetch`)
- Test: `Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Background/retry")
@MainActor
struct BackgroundRetryTests {
    @Test func retriesWithBackoffThenSucceeds() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 2           // fail #1 (initial), fail #2 (retry), then succeed
        await bg.settle()
        #expect(bg.probe.calls == 1)
        #expect(bg.entry.nextRetryDue == .seconds(1))   // scheduled at now(0) + backoff(0)
        await bg.advance(.seconds(1))            // retry #1 (fails)
        #expect(bg.probe.calls == 2)
        #expect(bg.entry.nextRetryDue == .seconds(3))   // now(1) + backoff(1)=2s
        await bg.advance(.seconds(2))            // retry #2 (succeeds)
        #expect(bg.probe.calls == 3)
        #expect(bg.entry.nextRetryDue == nil)           // reset on success
        #expect(bg.entry.failureCount == 0)
    }
    @Test func stopsAfterMaxRetries() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 2, baseDelay: .seconds(1), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 99          // always fails
        await bg.settle()                        // attempt 1
        await bg.advance(.seconds(1))            // retry 1
        await bg.advance(.seconds(2))            // retry 2
        #expect(bg.probe.calls == 3)             // 1 + 2 retries
        #expect(bg.entry.nextRetryDue == nil)    // exhausted — no further schedule
        await bg.advance(.seconds(60))
        #expect(bg.probe.calls == 3)             // no more attempts
    }
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter Background/retry` → FAIL (`nextRetryDue` never set).

- [ ] **Step 3: Implement** — extend `commitFetch`'s two branches in `Sources/SwiflowQuery/QueryClient.swift`:

```swift
        switch result {
        case .success(let value):
            entry.value = value
            entry.error = nil
            entry.lastFetched = clock.now()
            entry.failureCount = 0               // reset the retry cycle
            entry.nextRetryDue = nil
        case .failure(let err):
            entry.error = err
            // Leave `lastFetched` unchanged (stays stale). Schedule a retry if
            // attempts remain — increment BEFORE computing backoff so the
            // exponent is the explicit 0-indexed attempt.
            if entry.failureCount < entry.retry.maxRetries {
                let attempt = entry.failureCount
                entry.failureCount += 1
                entry.nextRetryDue = clock.now() + entry.retry.delay(forAttempt: attempt)
            }
        }
```
(The `tick` retry branch from Task 6 already fires when `now >= nextRetryDue`.)

- [ ] **Step 4: Run, expect pass** — `swift test --filter Background/retry` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
git commit -m "feat(query): retry failed fetches with backoff (commitFetch + tick)"
```

---

## Task 8: `focusChanged` — dedup-safe stale refetch

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (`focusChanged`)
- Test: `Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Background/focus")
@MainActor
struct BackgroundFocusTests {
    @Test func focusRefetchesStaleOnly() async {
        let bg = BG(staleTime: .seconds(10))
        await bg.settle()                        // fetch #1 at t=0
        bg.clock.advance(by: .seconds(5))        // still fresh (<10s)
        await bg.focus()
        #expect(bg.probe.calls == 1)             // fresh → skipped
        bg.clock.advance(by: .seconds(6))        // now 11s → stale
        await bg.focus()
        #expect(bg.probe.calls == 2)             // stale → refetched
    }
    @Test func focusSkipsWhenOptedOut() async {
        let bg = BG(staleTime: .zero, refetchOnFocus: false)  // always stale, but opted out
        await bg.settle()
        await bg.focus()
        #expect(bg.probe.calls == 1)
    }
    @Test func doubleFocusCoalesces() async {
        // A slow fetch stays in-flight across two focus events in one frame.
        let bg = BG(staleTime: .zero)
        await bg.settle()                        // fetch #1 done; entry now "fresh at t=0" but staleTime .zero → stale immediately
        bg.client.focusChanged(visible: true)    // spawns fetch #2 (in-flight, not awaited)
        bg.client.focusChanged(visible: true)    // inFlight != nil → no cancel/respawn
        await bg.settle()
        #expect(bg.probe.calls == 2)             // exactly one refetch, not two
    }
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter Background/focus` → FAIL (focus does nothing).

- [ ] **Step 3: Implement `focusChanged`** in `Sources/SwiflowQuery/QueryClient.swift`:

```swift
    package func focusChanged(visible: Bool) {
        guard visible else { return }
        for (key, entry) in entries
            where hasLiveSubscribers(key) && entry.refetchOnFocus {
            // Dedup-safe: only refetch if stale AND not already fetching. Do NOT
            // use forceStaleAndRefetch here — it cancels the in-flight fetch, so
            // a double focus (visibilitychange + focus) would cancel-respawn.
            if entry.inFlight == nil, needsFetch(entry, staleTime: entry.staleTime) {
                startFetch(for: key, entry: entry)
            }
        }
    }
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter Background/focus` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
git commit -m "feat(query): refetch stale queries on window focus (dedup-safe)"
```

---

## Task 9: Supersession clears the retry cycle

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient.swift` (`forceStaleAndRefetch`), `Sources/SwiflowQuery/QueryClient+Cache.swift` (`setQueryData`)
- Test: `Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Background/supersede")
@MainActor
struct BackgroundSupersedeTests {
    @Test func invalidateClearsPendingRetry() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(5), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 1           // initial fetch fails → schedules retry at t=5
        await bg.settle()
        #expect(bg.entry.nextRetryDue == .seconds(5))
        #expect(bg.entry.failureCount == 1)
        bg.client.invalidate(["k"])              // forceStaleAndRefetch → fresh fetch + reset
        await bg.settle()
        #expect(bg.entry.nextRetryDue == nil)    // pending retry cleared
        #expect(bg.entry.failureCount == 0)
    }
    @Test func setQueryDataClearsPendingRetry() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(5), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 1
        await bg.settle()
        #expect(bg.entry.nextRetryDue == .seconds(5))
        bg.client.setQueryData(["k"], ["optimistic"])
        #expect(bg.entry.nextRetryDue == nil)
        #expect(bg.entry.failureCount == 0)
    }
}
```

- [ ] **Step 2: Run, expect fail** — `swift test --filter Background/supersede` → FAIL (`nextRetryDue` still set).

- [ ] **Step 3: Implement** — add the two-field reset in both supersede sites.

In `Sources/SwiflowQuery/QueryClient.swift`, `forceStaleAndRefetch` (after the existing `entry.inFlight = nil`):
```swift
    private func forceStaleAndRefetch(_ key: QueryKey, _ entry: QueryEntry) {
        entry.lastFetched = nil          // force stale
        entry.generation += 1            // supersede any in-flight result
        entry.inFlight?.cancel()
        entry.inFlight = nil
        entry.nextRetryDue = nil         // a newer fetch supersedes the retry cycle
        entry.failureCount = 0
        if hasLiveSubscribers(key) {
            startFetch(for: key, entry: entry)
        }
    }
```

In `Sources/SwiflowQuery/QueryClient+Cache.swift`, `setQueryData` (after `entry.lastFetched = nil`, before `notify(key)`):
```swift
        entry.nextRetryDue = nil         // optimistic value supersedes the retry cycle
        entry.failureCount = 0
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter Background/supersede` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowQuery/QueryClient.swift Sources/SwiflowQuery/QueryClient+Cache.swift Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
git commit -m "fix(query): clear retry cycle on supersede (invalidate / setQueryData)"
```

---

## Task 10: `AsyncTestHarness` — own the clock + `advance`/`focus`

**Files:**
- Modify: `Sources/SwiflowTesting/AsyncTestHarness.swift`
- Test: `Tests/SwiflowTestingTests/AsyncTestHarnessBackgroundTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTestingTests/AsyncTestHarnessBackgroundTests.swift
import Testing
import Swiflow
import SwiflowQuery
@testable import SwiflowTesting

@MainActor private final class Poller: Component {
    var body: VNode {
        let s = query(PollQ())
        return .text(s.data.map(String.init) ?? "…")
    }
}
@MainActor private struct PollQ: Query {
    static var calls = 0
    var queryKey: QueryKey { ["poll"] }
    var refetchInterval: Duration? { .seconds(5) }
    func fetch() async throws -> Int { PollQ.calls += 1; return PollQ.calls }
}

@Suite("AsyncTestHarness/background")
@MainActor
struct AsyncTestHarnessBackgroundTests {
    @Test func advanceDrivesPolling() async throws {
        PollQ.calls = 0
        let h = AsyncTestHarness(Poller(), clock: ManualClock())
        try await h.settle()
        #expect(PollQ.calls == 1)
        try await h.advance(by: .seconds(5))
        #expect(PollQ.calls == 2)
    }
}
```
> `query(_:)` requires the render-active client; `AsyncTestHarness` already installs `RenderObserverBox.current` for its `TestRenderer`. `settle()` is `throws` (existing signature) — keep `try`.

- [ ] **Step 2: Run, expect fail** — `swift test --filter AsyncTestHarness/background` → FAIL (no `init(_:clock:)`, no `advance`).

- [ ] **Step 3: Implement** — in `Sources/SwiflowTesting/AsyncTestHarness.swift`:

(a) Store the clock and build the client from it. Replace the existing init:
```swift
    let renderer: TestRenderer
    let harness: TestHarness
    let clock: ManualClock

    public init<C: Component>(_ component: C, clock: ManualClock = ManualClock()) {
        self.clock = clock
        let r = TestRenderer(component, queryClient: QueryClient(clock: clock))
        self.renderer = r
        self.harness = TestHarness(r)
    }
```
> This replaces the old `init(_:queryClient:)`. If any existing caller passed a custom `queryClient`, migrate it to pass a `ManualClock` instead (search: `AsyncTestHarness(`). The default `ManualClock()` keeps the common case ergonomic.

(b) Add the two drivers (near `flush()`):
```swift
    /// Advance the test clock, fire one `tick`, and settle resulting refetches.
    public func advance(by delta: Duration) async throws {
        clock.advance(by: delta)
        renderer.queryClient.tick(now: clock.now())
        try await settle()
    }

    /// Simulate the window regaining focus, then settle resulting refetches.
    public func focus() async throws {
        renderer.queryClient.focusChanged(visible: true)
        try await settle()
    }
```

- [ ] **Step 4: Run, expect pass** — `swift test --filter AsyncTestHarness/background` → PASS. Then `swift build` to catch any old `AsyncTestHarness(_:queryClient:)` caller; fix each to `AsyncTestHarness(_:clock:)`.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowTesting/AsyncTestHarness.swift Tests/SwiflowTestingTests/AsyncTestHarnessBackgroundTests.swift
git commit -m "feat(testing): AsyncTestHarness owns the ManualClock; add advance(by:)/focus()"
```

---

## Task 11: SwiflowWeb production wiring (`BackgroundRevalidation`)

WASM-only JS triggers. Not host-unit-tested (like `RAFScheduler`); verified by host `swift build` (the `#if` compiles out cleanly) and the Task 12 WASM cross-compile + browser smoke.

**Files:**
- Create: `Sources/SwiflowWeb/BackgroundRevalidation.swift`
- Modify: `Sources/SwiflowWeb/Renderer.swift` (install in init; teardown)

- [ ] **Step 1: Implement the helper**

```swift
// Sources/SwiflowWeb/BackgroundRevalidation.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import SwiflowQuery

/// Installs the production background-revalidation triggers for one render root:
/// a ~1s `setInterval` driving `queryClient.tick(now:)`, and a `visibilitychange`
/// + window `focus` listener driving `queryClient.focusChanged(visible:)`.
///
/// Retains its `JSClosure`s for their lifetime (JavaScriptKit ref-counts them);
/// `stop()` releases them and tears down the JS handles, mirroring `RAFScheduler`.
@MainActor
final class BackgroundRevalidation {
    private weak var client: QueryClient?
    private let clock: any QueryClock
    private var intervalID: JSValue?
    private var tickClosure: JSClosure?
    private var focusClosure: JSClosure?

    init(client: QueryClient, clock: any QueryClock) {
        self.client = client
        self.clock = clock
    }

    func start() {
        let tick = JSClosure { [weak self] _ -> JSValue in
            guard let self, let client = self.client else { return .undefined }
            client.tick(now: self.clock.now())
            return .undefined
        }
        tickClosure = tick
        // setInterval(tick, 1000) — ~1s poll/backoff granularity.
        intervalID = JSObject.global.setInterval!(JSValue.object(tick), 1000)

        let onFocus = JSClosure { [weak self] _ -> JSValue in
            self?.client?.focusChanged(visible: true)
            return .undefined
        }
        focusClosure = onFocus
        let doc = JSObject.global.document.object
        _ = doc?.addEventListener!("visibilitychange", JSValue.object(onFocus))
        _ = JSObject.global.addEventListener!("focus", JSValue.object(onFocus))
    }

    func stop() {
        if let id = intervalID { _ = JSObject.global.clearInterval!(id); intervalID = nil }
        if let onFocus = focusClosure {
            let doc = JSObject.global.document.object
            _ = doc?.removeEventListener!("visibilitychange", JSValue.object(onFocus))
            _ = JSObject.global.removeEventListener!("focus", JSValue.object(onFocus))
        }
        tickClosure = nil
        focusClosure = nil
    }
}
#endif
```
> Verify the `JSObject.global.setInterval!(...)`/`document.addEventListener` call shapes against the JavaScriptKit version in `.build/checkouts/JavaScriptKit` during implementation (the dynamic-member-call form is `obj.method!(args)`, as in `RAFScheduler`); adjust unwrapping if the pinned API differs.

- [ ] **Step 2: Install + teardown in `Renderer`** (`Sources/SwiflowWeb/Renderer.swift`, all inside the existing `#if canImport(JavaScriptKit)`):

Add a stored property:
```swift
    private var backgroundRevalidation: BackgroundRevalidation?
```
In the Phase-3 (component-root) init, after the scheduler is assigned:
```swift
        let bg = BackgroundRevalidation(client: queryClient, clock: queryClient.clock)
        bg.start()
        backgroundRevalidation = bg
```
> `queryClient.clock` must be reachable from SwiflowWeb. If `clock` is `internal` on `QueryClient`, make it `package` (one-word change at its declaration: `package let clock: any QueryClock`). SwiflowWeb is the same package, so `package` is the correct visibility.

In `teardown()`, before nil-ing the scheduler:
```swift
        backgroundRevalidation?.stop()
        backgroundRevalidation = nil
```

- [ ] **Step 3: Verify host build** — `swift build` (the `#if canImport(JavaScriptKit)` body compiles out on host; confirm no host break and that the `package let clock` change compiles).

- [ ] **Step 4: Commit**
```bash
git add Sources/SwiflowWeb/BackgroundRevalidation.swift Sources/SwiflowWeb/Renderer.swift Sources/SwiflowQuery/QueryClient.swift
git commit -m "feat(web): wire background revalidation (setInterval tick + focus listener)"
```

---

## Task 12: TodoCRUD showcase + regenerate templates + full verification

**Files:**
- Modify: `examples/TodoCRUD/Sources/App/App.swift`
- Regenerate: `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Add polling to the showcase** — in `examples/TodoCRUD/Sources/App/App.swift`, give `TodoList` a poll interval (refetch-on-focus is already on by default):

```swift
struct TodoList: Query {
    var queryKey: QueryKey { ["todos"] }
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }   // live polling against the real API
    func fetch() async throws -> [Todo] {
        try await api.get("/todos", as: [Todo].self)
    }
}
```
Update the example README's "What it shows" to mention focus-refetch + 5s polling.

- [ ] **Step 2: Cross-compile the example to WASM** — `.build/debug/swiflow build --path examples/TodoCRUD` → "build complete." (Confirms the SwiflowWeb wiring + the new `Query` members compile for `wasm32`.)

- [ ] **Step 3: Regenerate embedded templates** (TodoCRUD changed — the `TemplateEmbedder` freshness test will fail otherwise; this is a known CI gate):
```bash
swift scripts/embed-templates.swift
swift test --filter TemplateEmbedder      # bit-for-bit freshness → PASS
```

- [ ] **Step 4: Full suite + commit**
```bash
swift test                                # full host suite green (OnChangeStorageTests is a known ~1/3 parallel flake — re-run if it alone fails)
git add examples/TodoCRUD/Sources/App/App.swift examples/TodoCRUD/README.md Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "feat(examples): TodoCRUD showcases focus-refetch + 5s polling"
```

- [ ] **Step 5: Manual browser smoke (optional, documented in spec §10)** — `docker compose -f examples/TodoCRUD/backend/docker-compose.yml up -d` + `swiflow dev --path examples/TodoCRUD --port 3002`: edit a todo via `curl` and watch it appear within ~5s (poll); switch tabs and back to see a focus refetch (⟳).

---

## Self-Review

**1. Spec coverage:**
- §4 public surface → Tasks 1 (RetryPolicy), 2 (Query members). ✓
- §5.1 entry state → Task 3. ✓
- §5.1 QueryObservation/reconcile copy → Task 4. ✓
- §5.2 tick poll → Task 6; retry branch present from Task 6, scheduling in Task 7. ✓
- §5.3 commitFetch retry + success reset → Task 7. ✓
- §5.4 focusChanged dedup-safe → Task 8. ✓
- §5.5 supersede clears retry → Task 9. ✓
- §6 SwiflowWeb wiring (always-on interval, JSClosure retain/teardown) → Task 11. ✓
- §7 harness clock ownership + advance/focus → Task 10. ✓
- §9 tests (poll/retry/focus/interplay/harness) → Tasks 6–10. ✓ (broken-poll-keeps-polling is covered transitively by retry-exhaustion + poll tests; never-succeeded-doesn't-poll → Task 6.)
- §10 example showcase → Task 12. ✓
- §11 invariants → exercised across Tasks 6–9 (dedup, supersession, no-subscribers via `hasLiveSubscribers` gate, retry-vs-poll precedence in Task 6's `tick`, absolute poll check). ✓

**2. Placeholder scan:** No TBD/TODO/"handle X". All code blocks are complete. The two "verify against the pinned JavaScriptKit API" notes (Task 11) are real review instructions for JS call shapes, not placeholders — the code is written and compilable as shown.

**3. Type consistency:** `RetryPolicy.delay(forAttempt:)` defined Task 1, used Task 7. `tick(now:)`/`focusChanged(visible:)` signatures consistent Tasks 5/6/8/10/11. `QueryObservation` field order (Task 4) matches the `BG` scaffold construction (Task 5) and the `reconcile` copy. `QueryEntry` fields (Task 3) match all reads (`nextRetryDue`, `failureCount`, `refetchInterval`, `refetchOnFocus`, `retry`, `staleTime`). `AsyncTestHarness(_:clock:)` (Task 10) matches its test usage. `package let clock` (Task 11) — the visibility bump is called out where first needed.

**Note for executor:** Tasks must run in order (later tasks' tests and the `BG` scaffold depend on earlier signatures). Task 10 changes `AsyncTestHarness`'s init signature — grep existing `AsyncTestHarness(` callers and migrate them in that task's Step 4.
