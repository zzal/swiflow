// Sources/SwiflowQuery/Query+Component.swift
import Swiflow

public extension Component {
    /// Observe a query from `body`. Returns the current cached snapshot and
    /// records interest with the active render root's client; the actual
    /// subscribe/fetch happens at the render boundary (`didEvaluate`).
    /// Outside a render (no active client) returns an optimistic loading state
    /// — a permanently-loading placeholder, warned about in DEBUG since it
    /// almost always means `query()` ran somewhere it can't work.
    func query<Q: Query>(_ q: Q) -> QueryState<Q.Value> {
        guard let observer = RenderObserverBox.current else {
            #if DEBUG
            QueryAmbientDiagnostics.warnOutsideRender()
            #endif
            return QueryState(isLoading: true, isFetching: true)
        }
        guard let client = observer as? QueryClient else {
            #if DEBUG
            QueryAmbientDiagnostics.warnWrongObserver(observerType: type(of: observer))
            #endif
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

#if DEBUG
/// Once-per-process warners for `query()`'s two silent-placeholder paths
/// (audit II Wave-3): before this, a `query()` with no usable client returned
/// a forever-loading snapshot with zero signal. `query()` runs on every body
/// evaluation, so each situation warns once rather than flooding the console
/// on every render. Tests reset via `_resetForTests()`.
@MainActor
enum QueryAmbientDiagnostics {
    private(set) static var warnedOutsideRender = false
    private(set) static var warnedWrongObserver = false

    static func _resetForTests() {
        warnedOutsideRender = false
        warnedWrongObserver = false
    }

    static func warnOutsideRender() {
        guard !warnedOutsideRender else { return }
        warnedOutsideRender = true
        swiflowWarn("""
        query() was called outside a render pass, so it returned a \
        permanently-loading QueryState — no fetch starts and no subscription \
        is made. Call query() from body. For handler-time work, use the \
        QueryState captured during the last render (e.g. its refetch()) or \
        Component.invalidate(...).
        """)
    }

    static func warnWrongObserver(observerType: Any.Type) {
        guard !warnedWrongObserver else { return }
        warnedWrongObserver = true
        swiflowWarn("""
        query() found a render observer of type \(observerType) instead of a \
        QueryClient, so it returned a permanently-loading QueryState — no \
        fetch starts and no subscription is made. This render root was not \
        set up for queries: render through Swiflow.render(into:) (which \
        installs a QueryClient), or construct your test harness with one.
        """)
    }
}
#endif
