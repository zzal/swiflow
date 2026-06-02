// Sources/SwiflowQuery/Query+Component.swift
import Swiflow

public extension Component {
    /// Observe a query from `body`. Returns the current cached snapshot and
    /// records interest with the active render root's client; the actual
    /// subscribe/fetch happens at the render boundary (`didEvaluate`).
    /// Outside a render (no active client) returns an optimistic loading state.
    func query<Q: Query>(_ q: Q) -> QueryState<Q.Value> {
        guard let client = RenderObserverBox.current as? QueryClient else {
            return QueryState(isLoading: true, isFetching: true)
        }
        return client.observe(q)
    }
}
