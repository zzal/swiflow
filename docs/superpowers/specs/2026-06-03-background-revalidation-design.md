# Background Revalidation — Design

> **Status:** Approved design (brainstormed 2026-06-03). Data-layer sub-project #3,
> building on the shipped Query Core + Mutations. Next: implementation plan.

## 1. Context

`SwiflowQuery` is a TanStack-Query/SWR-style data layer for Swiflow (Swift → WASM,
`@MainActor`, single-threaded). Query Core (typed `Query`, `QueryClient` cache,
stale-while-revalidate, prefix/tag invalidation) and Mutations (optimistic writes +
auto-invalidation) are shipped. The remaining sub-project is **background
revalidation**: keeping cached data fresh from trigger sources *beyond* the current
"observe during render" path, plus resilience against transient fetch failures.

Today the only fetch triggers are: a *new* observation at render (mount/key-change,
gated by `needsFetch`/`staleTime`), `invalidate(key|tag)`, and `setQueryData`
supersede (mutations). This adds three more, completing the TanStack-equivalent story.

## 2. Scope

**In v1:**
- **Refetch on window focus** — when the tab becomes visible/focused, refetch *stale*
  observed queries.
- **Polling / `refetchInterval`** — a query opts into periodic refetch.
- **Retry / backoff** — failed query fetches auto-retry with exponential backoff.

**Non-goals (deferred):**
- **Reconnect-refetch** (network online) — same "global trigger → refetch stale"
  mechanism as focus; a trivial fast-follow once the focus event port exists.
- **Mutation retry** — mutations are often non-idempotent; they do not auto-retry
  (matches TanStack). Out of scope.
- **Backoff jitter** — omitted so tests stay deterministic; an injectable jitter
  source is a later option.
- **Cache GC / eviction** — orthogonal; tracked separately.

## 3. Locked decisions

- **TanStack-style defaults:** `refetchOnFocus` **on** (stale-only, so it's cheap),
  `retry` **on** (3 attempts, exponential backoff), polling **off** unless
  `refetchInterval` is set. Per-query opt-out for focus/retry.
- **Clock-driven, no real timers in core.** Polling and retry-backoff are evaluated
  against the injected `QueryClock` by a `tick(now:)` the framework drives (one JS
  interval in production; the test harness advances `ManualClock`). Focus is a
  separate injected event. This reuses the `Clock`/`ManualClock` the whole layer is
  already tested with — one source of time truth, determinism for free.
- **Config lives on the self-describing `Query` protocol** as defaulted members, so
  every existing query compiles unchanged.

## 4. Public surface

New defaulted members on `Query` (added via a protocol extension):

```swift
public protocol Query {
    // ... existing: associatedtype Value; queryKey; tags; staleTime; fetch() ...
    var refetchInterval: Duration? { get }   // polling cadence
    var refetchOnFocus: Bool       { get }   // refetch-on-focus opt-out
    var retry: RetryPolicy         { get }
}

public extension Query {
    var refetchInterval: Duration? { nil }     // off unless set
    var refetchOnFocus: Bool       { true }
    var retry: RetryPolicy         { .default }
}
```

```swift
public struct RetryPolicy: Sendable, Equatable {
    public var maxRetries: Int       // extra attempts after the first failure
    public var baseDelay: Duration   // doubles per retry, capped at maxDelay
    public var maxDelay: Duration
    public init(maxRetries: Int, baseDelay: Duration, maxDelay: Duration)

    public static let none      = RetryPolicy(maxRetries: 0, baseDelay: .zero,       maxDelay: .zero)
    public static let `default` = RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))
}
```

Backoff before retry *n* (0-indexed) = `min(baseDelay × 2ⁿ, maxDelay)`. No jitter.

`tick(now:)` and `focusChanged(visible:)` are **`package`** (driven by the SwiflowWeb
wiring and the test harness — not user-facing), consistent with `inFlightTasks()`.

## 5. Engine (SwiflowQuery — pure, `ManualClock`-testable)

### 5.1 Per-entry state
`QueryEntry` gains state copied from the latest observation (as `tags` already is),
plus retry bookkeeping:

```swift
var staleTime: Duration          // promoted onto the entry (needed off the render path)
var refetchInterval: Duration?
var refetchOnFocus: Bool
var retry: RetryPolicy
var failureCount: Int = 0        // consecutive fetch failures
var nextRetryDue: Duration?      // clock time the next retry should fire
```

`QueryClient.QueryObservation` gains `refetchInterval` / `refetchOnFocus` / `retry`,
and `reconcile` copies all four (incl. `staleTime`) onto the entry, exactly where it
already copies `tags`/`boxedFetch`.

### 5.2 `tick(now:)`
Drives both polling and retry. For each entry with **live subscribers** and **no
in-flight fetch**:

```
if let due = entry.nextRetryDue, now >= due:
    entry.nextRetryDue = nil
    startFetch(key, entry)                 // retry
else if let interval = entry.refetchInterval,
        let last = entry.lastFetched, now - last >= interval:
    startFetch(key, entry)                 // poll  (independent of staleTime)
```
Retry takes precedence over poll. Polling refetches on its own cadence regardless of
`staleTime`. Both go through the existing `startFetch` (so dedup + `notify`/`isFetching`
+ the generation guard all apply unchanged).

### 5.3 Retry threading (in `commitFetch`)
The existing failure branch is extended:

```
case .failure(let err):
    entry.error = err                      // surfaced as today
    if entry.failureCount < entry.retry.maxRetries:
        entry.nextRetryDue = clock.now() + backoff(entry.failureCount)
        entry.failureCount += 1
    // else: retries exhausted — error stays surfaced until the next trigger
case .success(let value):
    entry.failureCount = 0                 // reset
    entry.nextRetryDue = nil
    // ... existing success handling ...
```
Any successful fetch (from any trigger) resets the retry cycle. A new render
observation / `invalidate` / focus / poll also restarts a fetch and thus the cycle.
The generation guard already drops a superseded retry result.

### 5.4 `focusChanged(visible:)`
```
guard visible else { return }
for (key, entry) in entries where hasLiveSubscribers(key) && entry.refetchOnFocus:
    if needsFetch(entry, staleTime: entry.staleTime):     // stale-only
        forceStaleAndRefetch(key, entry)
```
Stale-gating keeps focus cheap — only entries past their `staleTime` refetch, and the
`inFlight` guard prevents storms when focus and visibility both fire.

## 6. Production wiring (SwiflowWeb — WASM-only)

A new `BackgroundRevalidation` helper, behind `#if canImport(JavaScriptKit)` like the
rest of the JS layer, installed by `Renderer` alongside the `RAFScheduler`:
- a JS `visibilitychange` + window `focus` listener → `queryClient.focusChanged(visible:)`;
- one `setInterval(~1s)` → `queryClient.tick(clock.now())`.

Both are torn down on unmount (mirroring the `RAFScheduler` teardown). The ~1s tick is
the poll/backoff granularity — fine for second-scale intervals (`baseDelay` is ≥ 1s).
**Optional refinement** (note, not required for v1): pause the interval when no entry
has a `refetchInterval` and no `nextRetryDue` is pending, re-arming when one appears,
to avoid an always-on timer.

## 7. Test harness (SwiflowTesting)

`AsyncTestHarness` (built on a `ManualClock`) gains:
- **`advance(by: Duration)`** — `clock.advance(by:)` → `client.tick(clock.now())` → `settle()`.
- **`focus()`** — `client.focusChanged(visible: true)` → `settle()`.

So a polling / retry / focus test reads exactly like today's staleness tests: advance
the clock, then assert. No new time-control concept.

## 8. Files

**New:**
- `Sources/SwiflowQuery/RetryPolicy.swift` — pure value type.
- `Sources/SwiflowWeb/BackgroundRevalidation.swift` — JS `visibilitychange`/`focus` +
  `setInterval` wiring (WASM-only).

**Modified:**
- `Sources/SwiflowQuery/Query.swift` — protocol members + defaulted extension.
- `Sources/SwiflowQuery/QueryEntry.swift` — `staleTime` + background/retry state.
- `Sources/SwiflowQuery/QueryClient.swift` — `tick(now:)`, `focusChanged(visible:)`,
  `QueryObservation` fields, `reconcile` copy, `commitFetch` retry scheduling, the
  `backoff(_:)` helper.
- `Sources/SwiflowWeb/Renderer.swift` — install/teardown the `BackgroundRevalidation`.
- `Sources/SwiflowTesting/AsyncTestHarness.swift` — `advance(by:)` + `focus()`.

## 9. Testing strategy (deterministic, `ManualClock`-driven)

- **Polling:** `refetchInterval` query → `advance(by: interval)` refetches; advancing
  less than the interval does not; polling is independent of `staleTime`.
- **Retry:** a failing fetch schedules `nextRetryDue`; `advance` past the backoff fires
  the retry; backoff doubles and caps at `maxDelay`; after `maxRetries` the error stays
  surfaced and no further retries fire; a later success resets `failureCount`.
- **Focus:** `focus()` refetches stale + `refetchOnFocus` entries only; skips fresh
  entries, opted-out entries (`refetchOnFocus == false`), and entries with no live
  subscribers.
- **Interplay:** a tick/focus refetch superseded by a key-change/`invalidate` is dropped
  by the generation guard; `isFetching` toggles for background refetches; in-flight
  dedup prevents double-fire.
- **Harness:** `advance`/`focus` drive `tick`/`focusChanged` and settle to a fixed point.

The production `setInterval`/`visibilitychange` wiring is smoke-tested in the browser
(à la `SystemQueryClock`/`RAFScheduler`), not unit-tested.

## 10. Example showcase (TodoCRUD)

Extend `examples/TodoCRUD`:
- **Refetch-on-focus** — switch tabs and back; the list refreshes from the real API
  (the ⟳ spinner flashes).
- **Polling** — give `TodoList` a `refetchInterval` (e.g. a few seconds); edits made
  out-of-band (e.g. via `curl`) appear on the next poll. Genuinely demoable now that
  there's a live backend (vs. the old `Task.sleep` stubs).

## 11. Edge cases & invariants

- **Dedup:** `tick` only fetches entries with `inFlight == nil`; concurrent triggers
  coalesce.
- **Supersession:** background refetches use the existing generation guard — a stale or
  superseded result never clobbers a newer value (incl. an optimistic mutation write).
- **No live subscribers:** `tick`/`focusChanged` skip entries with no live subscribers
  (no background work for unmounted components); the entry stays in cache, eligible
  again when re-observed.
- **Retry vs. poll precedence:** retry fires before poll for the same entry on a tick.
- **Granularity:** poll/backoff resolution = tick rate (~1s); `baseDelay ≥ 1s`.
- **Determinism:** no wall-clock sleeps, no randomness in core — all time flows through
  the injected `QueryClock`.
