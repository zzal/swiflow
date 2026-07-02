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
    /// Clock time the last fetch SETTLED (success or failure). Paces polling:
    /// after retries exhaust, `lastFetched` freezes at the last success, and
    /// gating polls on it alone would refire every tick (audit Wave-1 #6).
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
    let fetching = entry.inFlight != nil
    let data = entry.value as? V
    return QueryState(
        data: data,
        error: entry.error,
        isLoading: data == nil && fetching,
        isFetching: fetching
    )
}
