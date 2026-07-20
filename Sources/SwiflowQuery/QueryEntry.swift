// Sources/SwiflowQuery/QueryEntry.swift
import Swiflow

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
    /// Clock time the last fetch SETTLED (success or failure). Paces polling:
    /// after retries exhaust, `lastFetched` freezes at the last success, and
    /// gating polls on it alone would refire every tick.
    var lastSettled: Duration?
    /// Bumped on supersede/invalidate; a resolving fetch commits only if the
    /// entry's generation still matches the one it captured at spawn.
    var generation: Int = 0
    /// The currently running fetch, if any (dedup + cancellation handle).
    var inFlight: Task<Void, Never>?
    /// Cross-cutting families this entry belongs to (from the latest query).
    var tags: Set<QueryTag> = []
    /// Promoted from the latest observation (needed off the render path, by
    /// `tick`/`focusChanged`). Defaults apply until `reconcile` copies the
    /// query's values on.
    var staleTime: Duration = .zero
    var refetchInterval: Duration?
    var refetchOnFocus: Bool = true
    var retry: RetryPolicy = .default
    /// Consecutive fetch failures; reset to 0 on any success or supersede.
    var failureCount: Int = 0
    /// Clock time the next retry should fire; `nil` = no pending retry.
    var nextRetryDue: Duration?
    /// Promoted from the latest observation, like `staleTime`.
    var gcTime: Duration = .seconds(300)
    /// Clock time this entry lost its last live subscriber; `nil` while
    /// observed. Stamped/cleared by `tick`'s GC sweep.
    var unobservedSince: Duration?
    /// The latest query's fetch, capturing its latest dependencies. Used to
    /// refetch on invalidation. `@MainActor` so calling it needs no Sendable.
    var boxedFetch: (@MainActor () async throws -> Any)?
}

// MARK: - Supersede (the reset contract)

extension QueryEntry {
    /// Invalidate this entry's in-flight world: any resolving fetch is dropped
    /// (`commitFetch`'s generation guard) and cancelled, the retry ladder is
    /// void, and the entry is forced stale so the next trigger refetches.
    ///
    /// This is THE reset contract — `forceStaleAndRefetch` and `setQueryData`
    /// both route through here so the transition can't drift apart again (it
    /// had, hand-written: one cleared `error`, the other didn't). The one
    /// DELIBERATE difference between the callers is `clearError`:
    /// - `false` (invalidate): no new truth yet — keep the last-known error
    ///   visible alongside the last-known data (SWR) until the refetch
    ///   settles and overwrites both. The error persists until proven
    ///   otherwise.
    /// - `true` (optimistic write): the written value IS the new truth; a
    ///   lingering error would contradict it.
    func supersede(clearError: Bool) {
        lastFetched = nil            // force stale
        generation += 1              // a resolving fetch commits only on match
        inFlight?.cancel()
        inFlight = nil
        resetRetryCycle()            // the supersede owns the next attempt
        if clearError { error = nil }
    }

    /// Void the retry ladder. Shared by `supersede` and `commitFetch`'s
    /// success path — which resets retries WITHOUT superseding: it IS the
    /// committing fetch, so there is nothing to bump or cancel.
    func resetRetryCycle() {
        failureCount = 0
        nextRetryDue = nil
    }
}

/// Project an entry into a typed snapshot. `nil` entry → optimistic loading.
/// `client`/`key` ride along (when the caller has them) so the snapshot's
/// `refetch()` can reach the owning root's client from a handler.
@MainActor
func makeSnapshot<V>(
    from entry: QueryEntry?, as _: V.Type,
    client: QueryClient? = nil, key: QueryKey? = nil
) -> QueryState<V> {
    var state: QueryState<V>
    if let entry {
        let fetching = entry.inFlight != nil
        let data = entry.value as? V
        #if DEBUG
        // A cached value that fails the typed read is never intentional: two
        // query types are sharing one key with different `Value` types, and
        // `as?` degrades that to data == nil — a permanent spinner for the
        // mismatched reader with zero signal (audit II guardrail; the write
        // path's `OptimisticOutcome.typeMismatch` already shouts).
        if let cached = entry.value, data == nil {
            swiflowDiagnostic("""
            Query value type mismatch\(key.map { " for key \($0.diagnosticText)" } ?? ""): \
            the cache holds \(type(of: cached)) but this reader asked for \
            \(V.self). Two query types are sharing one key with different \
            Value types — the mismatched reader sees data == nil forever. \
            Give each Value type its own key (e.g. a distinct prefix).
            """)
        }
        #endif
        state = QueryState(
            data: data,
            error: entry.error,
            isLoading: data == nil && fetching,
            isFetching: fetching
        )
    } else {
        state = QueryState(isLoading: true, isFetching: true)
    }
    state.client = client
    state.key = key
    return state
}
