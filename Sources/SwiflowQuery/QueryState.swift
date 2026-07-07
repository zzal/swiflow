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

    /// Captured at observation time so `refetch()` can reach the OWNING
    /// root's client from an event handler — root-correct by construction,
    /// unlike any ambient. `weak`: a snapshot captured into a long-lived
    /// closure must not keep a torn-down root's client alive; `refetch()`
    /// degrades to a no-op instead.
    weak var client: QueryClient?
    /// The observed query's cache key, paired with `client`.
    var key: QueryKey?

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

    /// Imperatively force this query stale and refetch it — the "Refresh"
    /// button. Exactly an exact-key invalidate: any in-flight fetch is
    /// superseded (cancelled and, with `FetchTransport`, aborted at the
    /// network layer), the entry is forced stale, and a refetch starts if the
    /// query has live subscribers. The last error stays visible until the
    /// refetch settles (the invalidate policy), and `isFetching` toggles
    /// notify subscribers, so a spinner bound to this state just works.
    ///
    /// No-op when the snapshot didn't come from a live render observation
    /// (`query(_:)` outside a render) or the owning root was torn down.
    @MainActor
    public func refetch() {
        guard let client, let key else { return }
        client.invalidate(key, exact: true)
    }
}
