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
