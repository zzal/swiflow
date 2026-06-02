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
