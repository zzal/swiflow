# Background Revalidation — Design

> **Status:** Rev 2 — brainstormed 2026-06-03, swift-innovator-expert review folded in
> (harness owns the test clock; focus uses the dedup-safe fetch path; supersede clears
> the retry cycle; backoff exponent clamped; the pause-when-idle tick refinement
> dropped). Data-layer sub-project #3, building on the shipped Query Core + Mutations.
> Next: implementation plan.

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

`maxRetries` is the number of retries *after* the initial fetch (total attempts =
`maxRetries + 1`); `maxRetries: 0` (`.none`) disables retry. Backoff before retry *n*
(0-indexed) = `min(baseDelay × 2ⁿ, maxDelay)`. The exponent is **clamped** before the
shift (`baseDelay`'s `Int64` attoseconds overflow well before `n = 63`, and a user may
pass a large `maxRetries`), so `backoff(_:_:)` computes
`min(baseDelay × (1 << min(n, 40)), maxDelay)`. No jitter (keeps tests deterministic).

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
The existing failure branch is extended — increment the attempt counter *before*
computing the backoff, so the exponent is the explicit 0-indexed attempt:

```
case .failure(let err):
    entry.error = err                      // surfaced as today
    if entry.failureCount < entry.retry.maxRetries:
        let attempt = entry.failureCount   // 0,1,2,… — also the backoff exponent
        entry.failureCount += 1
        entry.nextRetryDue = clock.now() + backoff(attempt, entry.retry)
    // else: retries exhausted — error stays surfaced until the next success
case .success(let value):
    entry.failureCount = 0                 // reset the retry cycle
    entry.nextRetryDue = nil
    // ... existing success handling (value / error = nil / lastFetched = now) ...
```
A successful fetch **from any trigger** (render observation, `invalidate`, focus, poll,
or retry) routes through `.success` and resets the cycle; supersession also resets it
(§5.5). The generation guard already drops a superseded retry result.

### 5.4 `focusChanged(visible:)`
```
guard visible else { return }
for (key, entry) in entries where hasLiveSubscribers(key) && entry.refetchOnFocus:
    if entry.inFlight == nil, needsFetch(entry, staleTime: entry.staleTime):  // stale-only, dedup-safe
        startFetch(for: key, entry: entry)
```
Focus uses `startFetch` directly — **not** `forceStaleAndRefetch`. The latter cancels any
in-flight fetch and bumps the generation; that's right for *invalidation* but wrong for
focus, where `visibilitychange` + window `focus` can both fire in one frame — the second
call would cancel-and-respawn the fetch the first just started (spinner restart / wasted
request). Gating on `inFlight == nil` + `needsFetch` makes focus idempotent within a
frame and cheap (only stale entries refetch).

### 5.5 Supersession resets the retry cycle
`forceStaleAndRefetch` (invalidate / mutation refetch) and `setQueryData` (optimistic
write) already bump the generation and cancel `inFlight`; they additionally **clear
`nextRetryDue` and reset `failureCount`**. A newer fetch (or an optimistic value)
supersedes the old one, so a pending retry from the old fetch is moot — without this, a
`nextRetryDue` left over from a pre-supersede failure would fire a spurious extra fetch
on a later tick.

## 6. Production wiring (SwiflowWeb — WASM-only)

A new `BackgroundRevalidation` helper, behind `#if canImport(JavaScriptKit)` like the
rest of the JS layer, installed by `Renderer` alongside the `RAFScheduler`:
- a JS `visibilitychange` + window `focus` listener → `queryClient.focusChanged(visible:)`;
- one `setInterval(~1s)` → `queryClient.tick(clock.now())`.

The ~1s tick is the poll/backoff granularity — fine for second-scale intervals
(`baseDelay` is ≥ 1s). The interval is **always-on for v1** (a 1s dictionary scan in one
tab is negligible). A "pause when nothing polls and no retry is pending" optimization is
explicitly **out of scope**: it would need `commitFetch` to call back into the JS layer
to re-arm the interval whenever a failure sets `nextRetryDue`, and without that hook a
retry scheduled while the interval is paused would never fire — a latent stuck-retry
bug. Defer until there's evidence the always-on timer matters.

Both the interval and the listeners are torn down on unmount, mirroring
`RAFScheduler.teardown`. As with `RAFScheduler`, the helper must **retain its
`JSClosure`s** (the interval callback + the `visibilitychange`/`focus` handlers) for
their lifetime and release them on teardown (`clearInterval` + `removeEventListener`), so
they survive across event-loop turns.

## 7. Test harness (SwiflowTesting)

`AsyncTestHarness` can't reach the client's `clock` (it does a plain `import
SwiflowQuery`, and `QueryClient.clock` is `internal` + typed `any QueryClock`, exposing
only `now()`). So the harness **owns the `ManualClock` directly**: `init` constructs (or
accepts) a `ManualClock`, builds the `QueryClient(clock:)` with it, and retains the
reference. (This changes the `init` signature — fine pre-1.0; the harness genuinely needs
the deterministic clock.) It then gains:
- **`advance(by: Duration)`** — `clock.advance(by:)` → `client.tick(now: clock.now())` → `settle()`.
- **`focus()`** — `client.focusChanged(visible: true)` → `settle()`.

`tick`/`focusChanged` are `package`, so the harness (same package) calls them directly. A
polling / retry / focus test then reads exactly like today's staleness tests: advance the
clock, then assert. No new time-control concept.

## 8. Files

**New:**
- `Sources/SwiflowQuery/RetryPolicy.swift` — pure value type.
- `Sources/SwiflowWeb/BackgroundRevalidation.swift` — JS `visibilitychange`/`focus` +
  `setInterval` wiring (WASM-only).

**Modified:**
- `Sources/SwiflowQuery/Query.swift` — protocol members + defaulted extension.
- `Sources/SwiflowQuery/QueryEntry.swift` — `staleTime` + background/retry state.
- `Sources/SwiflowQuery/QueryClient.swift` — `tick(now:)`, `focusChanged(visible:)` (the
  dedup-safe focus path), `QueryObservation` fields, `reconcile` copy, `commitFetch` retry
  scheduling + success-reset, `forceStaleAndRefetch` clearing the retry cycle, the
  `backoff(_:_:)` helper.
- `Sources/SwiflowQuery/QueryClient+Cache.swift` — `setQueryData` clearing the retry cycle.
- `Sources/SwiflowWeb/Renderer.swift` — install/teardown the `BackgroundRevalidation`
  (retain the `JSClosure`s; `clearInterval` + `removeEventListener` on teardown).
- `Sources/SwiflowTesting/AsyncTestHarness.swift` — own the `ManualClock` (init signature
  change) + `advance(by:)` / `focus()`.

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
  by the generation guard; a double focus (`visibilitychange` + `focus`) does **not**
  cancel-respawn the in-flight fetch (§5.4); `invalidate`/`setQueryData` clear a pending
  `nextRetryDue` so no spurious retry fires afterward (§5.5); `isFetching` toggles for
  background refetches.
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

- **Dedup:** `tick` and `focusChanged` only fetch entries with `inFlight == nil`;
  concurrent triggers (incl. `visibilitychange` + `focus` in one frame) coalesce instead
  of cancel-respawning (§5.4).
- **Supersession:** background refetches use the existing generation guard — a stale or
  superseded result never clobbers a newer value (incl. an optimistic mutation write) —
  and supersession also clears the entry's retry cycle (§5.5).
- **No live subscribers:** `tick`/`focusChanged` skip entries with no live subscribers
  (no background work for unmounted components); the entry stays in cache, eligible again
  when re-observed.
- **Retry vs. poll precedence:** retry fires before poll for the same entry on a tick.
- **Never-succeeded entries don't poll:** the poll branch requires `lastFetched != nil`,
  so a query still in initial load / retrying never also polls.
- **Broken polling endpoint:** a failing poll enters the retry cycle (≤ `maxRetries`); once
  retries are exhausted it keeps polling at its interval (each failure re-surfaces the
  error; `failureCount` stays pinned) until a poll succeeds and resets it. Matches
  TanStack — deliberately not a hard stop.
- **`entries` not mutated during iteration:** `tick`/`focusChanged` call `startFetch`,
  which mutates only the entry's fields + `subscribers` (via `notify`) — never the
  `entries` dictionary (only `reconcile` inserts). The iteration is safe; a future
  "create entry on poll" change must preserve this.
- **Granularity:** poll/backoff resolution = tick rate (~1s); `baseDelay ≥ 1s`. The poll
  check is absolute (`now - lastFetched >= interval`) — polls fire up to ~1s late, never
  drift.
- **Determinism:** no wall-clock sleeps, no randomness in core — all time flows through
  the injected `QueryClock`.
