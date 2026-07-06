// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// Scoped: callers open a named scope before invoking `body`; all IDs
/// registered while a scope is open are tracked against that scope.
/// Closing the scope evicts every ID registered inside it, ensuring
/// `.on(_:perform:)` closures cannot outlive their owning Component instance.
///
/// Scopes are identified by stable `ScopeID` values returned from
/// `openScope(debugName:)`. `closeScope(_:)` evicts by ID, not by stack
/// position, so sibling components can be destroyed in any order without
/// cross-contamination.
///
/// `package` access: visible to `SwiflowDOM` (same package) but not to
/// application code that imports Swiflow as a library dependency.
package final class HandlerRegistry: @unchecked Sendable {
    // Thread isolation: mutated only during @MainActor render passes
    // (register/closeScope) and read by the @MainActor dispatcher; wasm is
    // single-threaded. The statics stay nonisolated(unsafe) (not @MainActor)
    // because the class witnesses non-isolated contexts in host-side tests.
    nonisolated(unsafe) private static var nextID: Int = 0
    nonisolated(unsafe) private static var globalTable: [Int: EventHandler] = [:]
    private var nextScopeID: Int = 0
    private var handlers: [Int: EventHandler] = [:]

    private struct Scope {
        var debugName: String
        var ids: [Int]
    }
    private var scopes: [ScopeID: Scope] = [:]
    private var openScopes: [ScopeID] = []      // open scope IDs in push order; last = top
    private var handlerToScope: [Int: ScopeID] = [:]  // handlerID → ScopeID for O(1) removal
    private var activeScopeID: ScopeID? = nil   // set during withScope(_:_:)

    package init() {}

    // MARK: - Two-map bookkeeping (single mutation funnel)
    //
    // A handler lives in BOTH maps, which serve genuinely different consumers
    // and so cannot be collapsed into one:
    //   • `handlers` (this instance) backs `dispatch(id:)`, used by
    //     `TestRenderer` — per-instance so parallel host tests don't
    //     cross-contaminate through a shared static.
    //   • `globalTable` (static, all instances) backs `dispatchGlobal(id:)`,
    //     used by the single `window.__swiflowDispatch` JS callback, which
    //     receives only an integer ID and can't know which registry owns it.
    // Every add/remove funnels through this one insert/evict pair (plus the
    // scope attribution), so the two maps can never drift — previously a missed
    // hand-sync in one of four methods would leak a `globalTable` entry (a
    // handler that outlives its component) or corrupt scope diagnostics.

    /// Adds `handler` to both maps and attributes it to `scope`, if any.
    private func insert(_ handler: EventHandler, scope: ScopeID?) {
        let id = handler.id
        handlers[id] = handler
        Self.globalTable[id] = handler
        if let scope {
            scopes[scope]?.ids.append(id)
            handlerToScope[id] = scope
        }
    }

    /// Removes handler `id` from both maps and from its owning scope's id list.
    /// Idempotent — evicting an unknown id is a no-op.
    private func evict(_ id: Int) {
        handlers.removeValue(forKey: id)
        Self.globalTable.removeValue(forKey: id)
        if let scopeID = handlerToScope.removeValue(forKey: id) {
            scopes[scopeID]?.ids.removeAll { $0 == id }
        }
    }

    // MARK: - Scope management

    /// Opens a new scope and returns its stable `ScopeID`. The ID must be
    /// saved and passed to `closeScope(_:)` at unmount time.
    ///
    /// `debugName` is used only by `countPerScope()` for diagnostics; it is
    /// not structurally load-bearing and two scopes may share the same name.
    package func openScope(debugName: String = "") -> ScopeID {
        let id = ScopeID(raw: nextScopeID); nextScopeID += 1
        scopes[id] = Scope(debugName: debugName, ids: [])
        openScopes.append(id)
        return id
    }

    /// Closes the scope identified by `scope`, evicting every handler it owns
    /// from the registry. Safe to call in any order relative to other open
    /// scopes — lookup is by stable `ScopeID`, not by stack position.
    package func closeScope(_ scope: ScopeID) {
        guard let s = scopes.removeValue(forKey: scope) else { return }
        openScopes.removeAll { $0 == scope }
        // The scope entry is already gone (above), so `evict`'s scope-list
        // cleanup no-ops; it still drops each id from both maps + handlerToScope.
        for hid in s.ids { evict(hid) }
    }

    /// Runs `body` with `scope` as the active scope. Handlers registered
    /// during `body` are tracked against `scope`, regardless of what scopes
    /// are currently on top of the open-scope list. Saves and restores the
    /// previous active scope, so nested calls compose correctly.
    ///
    /// Use this around every component `body` evaluation during both mount
    /// and update so handler ownership is always correct — even when sibling
    /// or descendant scopes are simultaneously open.
    @discardableResult
    package func withScope<T>(_ scope: ScopeID, _ body: () -> T) -> T {
        let previous = activeScopeID
        activeScopeID = scope
        defer { activeScopeID = previous }
        return body()
    }

    /// Variant of `withScope(_:_:)` that is a no-op when `scope` is `nil`.
    /// Allows callers to pass an optional `ScopeID` without extra unwrapping
    /// when a non-component node has no associated scope.
    @discardableResult
    package func withScope<T>(_ scope: ScopeID?, _ body: () -> T) -> T {
        guard let scope else { return body() }
        return withScope(scope, body)
    }

    // MARK: - Handler management

    /// Registers a closure and returns the `EventHandler`. When called inside
    /// `withScope(_:_:)`, the handler is attributed to that scope and evicted
    /// when the scope closes. When called outside any `withScope` the handler
    /// is permanent — it persists until `remove(id:)` is called explicitly.
    ///
    /// Calling `register` while scopes are open but outside `withScope` is a
    /// programmer error: the handler is permanent even though the caller likely
    /// intends it to be scoped. This fires `swiflowDiagnostic` in DEBUG builds.
    @discardableResult
    package func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = Self.nextID; Self.nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        insert(h, scope: activeScopeID)
        if activeScopeID == nil && !openScopes.isEmpty {
            swiflowDiagnostic(
                "Handler registered outside withScope(_:_:) while \(openScopes.count) scope(s) are open. " +
                "The handler is permanent and will not be evicted when the scope(s) close — this is almost " +
                "certainly unintended. Wrap the registration: withScope(scopeID) { registry.register { ... } }."
            )
        }
        return h
    }

    package func handler(forID id: Int) -> EventHandler? { handlers[id] }

    /// Removes a handler from the registry and from its owning scope.
    /// This keeps scope ID arrays compact across re-renders (handlers swapped
    /// out by `diffHandlers` are pruned immediately, not left as stale entries
    /// that accumulate until the component unmounts).
    package func remove(id: Int) {
        evict(id)
    }

    package func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

    deinit {
        // Drop this instance's handlers from the shared global table so a
        // released registry doesn't leak dispatch entries. Snapshot the keys
        // (`evict` mutates `handlers`) and funnel through the same eviction path.
        for id in Array(handlers.keys) { evict(id) }
    }

    package static func dispatchGlobal(id: Int, event: EventInfo) {
        globalTable[id]?.invoke(event)
    }

    // MARK: - Diagnostics

    /// Returns handler counts per scope debug name. Used by `__swiflow__.handlers()`.
    package func countPerScope() -> [String: Int] {
        var result: [String: Int] = [:]
        for (_, scope) in scopes {
            result[scope.debugName, default: 0] += scope.ids.count
        }
        return result
    }
}
