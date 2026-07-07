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

    /// Imperatively invalidate exactly `query`'s cache slot — the typed
    /// spelling (the key comes from the query type, like
    /// `Invalidation.exact(_:)`). Safe to call from event handlers.
    func invalidate<Q: Query>(_ query: Q) {
        Self.imperativeClient()?.invalidate(query.queryKey, exact: true)
    }

    /// Imperatively invalidate `key` (and, unless `exact`, every key under
    /// it). Safe to call from event handlers.
    func invalidate(_ key: QueryKey, exact: Bool = false) {
        Self.imperativeClient()?.invalidate(key, exact: exact)
    }

    /// Imperatively invalidate every query tagged `tag`. Safe to call from
    /// event handlers.
    func invalidate(tag: QueryTag) {
        Self.imperativeClient()?.invalidate(tag: tag)
    }

    /// The client for imperative (handler-time) cache operations: the active
    /// render's observer when called during `body`, else the most recently
    /// rendered root's (`RenderObserverBox.lastRendered`) — render context is
    /// uninstalled after every diff pass, and handlers run between renders.
    /// Single-root apps always resolve their own client; with multiple render
    /// roots a handler resolves the most recently rendered one. Before the
    /// first render there is nothing cached, so `nil` → no-op is exact.
    /// For per-observation refetch, prefer `QueryState.refetch()` — its
    /// captured client is root-correct by construction.
    private static func imperativeClient() -> QueryClient? {
        (RenderObserverBox.current ?? RenderObserverBox.lastRendered) as? QueryClient
    }
}
