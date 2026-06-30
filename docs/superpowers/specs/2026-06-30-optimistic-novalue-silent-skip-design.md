# Fix #96 — `.noValue` optimistic edit should skip silently, not trap

**Goal:** Firing a mutation whose `optimistic()` edits a query with **no cached value yet** (not subscribed / not yet fetched) must NOT crash in DEBUG. It should silently skip that optimistic layer — matching `OptimisticEdit`'s documented intent — while the mutation's `perform` + invalidation still run and reconcile.

**Issue:** #96. Surfaced by the Theme A query fuzz suite (PR #95).

## Problem

`MutationRuntime.beginOptimistic` (`Sources/SwiflowQuery/MutationState.swift`) handles the `.noValue` outcome by calling `swiflowDiagnostic(...)`, which is a `preconditionFailure` in DEBUG (`Sources/Swiflow/Reactivity/Diagnostics.swift`) — it **traps**:

```swift
case .noValue:
    #if DEBUG
    swiflowDiagnostic("OptimisticEdit.update: no cached value for key \(edit.key) — edit skipped.")
    #endif
```

This contradicts `OptimisticEdit`'s own design (`Sources/SwiflowQuery/OptimisticEdit.swift`), which separates a **benign skip** (`.noValue` — *"skipped silently; nothing on screen reads it"*) from a **programmer error** (`.typeMismatch` — *"shout"*). So "optimistic mutate before the query has loaded" — a legitimate pattern — crashes dev instead of no-op'ing.

No test pins the trap: `MutationCoreTypesTests.updateReportsNoValueWhenAbsent` asserts `OptimisticEdit.apply(nil)` returns `.noValue` (the outcome), not the runtime's reaction.

## Change

In `beginOptimistic`, make `.noValue` a true silent skip — remove the `#if DEBUG swiflowDiagnostic(...)` body so the case does nothing (with a short comment: the query isn't loaded yet, so there's nothing to optimistically transform; the mutation's `perform` + the subsequent invalidation/refetch reconcile). Keep `.typeMismatch` exactly as-is (`assertionFailure` — a genuine "edit targets the wrong query" programmer error). This preserves the design's "stay quiet for the benign case, shout for the programmer error" split.

No change to `OptimisticEdit` (its `.noValue` doc already says "skipped silently" — the code now matches). No change to the diff, the query client, or the fuzz suite's existing upfront-subscribe (harmless, slightly stronger coverage).

## Testing

A focused regression test reusing the existing harness in `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift` (`FuzzWorld` + `AppendMut`):

- Install `_swiflowDiagnosticOverride` (capture, don't trap).
- On a `FuzzWorld`, fire `mutate(AppendMut(id: 7, model:), v)` for a list id `7` that was **never subscribed** (so its query has no cached value → `.noValue`), then `settle()`.
- Assert: (a) **no diagnostic captured** (silent skip — before the fix this string was emitted / would trap); (b) the mutation's `perform` still ran (`model.value(7) == [v]`).

Restore the override after the test.

## Acceptance criteria

1. A mutation optimistically editing an unsubscribed/unloaded query does NOT trap in DEBUG and emits no diagnostic; its `perform` still runs.
2. `.typeMismatch` still traps in DEBUG (unchanged).
3. `MutationCoreTypesTests` and the full host suite stay green.

## Out of scope

- Adding a non-trapping "dev log" primitive (there isn't one; `.noValue` is simply silent per the doc).
- Any change to `OptimisticEdit`, the diff, or `QueryClient`.
