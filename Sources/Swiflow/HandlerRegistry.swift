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
/// `package` access: visible to `SwiflowWeb` (same package) but not to
/// application code that imports Swiflow as a library dependency.
package final class HandlerRegistry: @unchecked Sendable {
    private var nextID: Int = 0
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
        for hid in s.ids {
            handlers.removeValue(forKey: hid)
            handlerToScope.removeValue(forKey: hid)
        }
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

    /// Registers a closure and returns the `EventHandler`. Tracks the ID
    /// against `activeScopeID` when set (inside `withScope`), otherwise
    /// against the most-recently-opened scope (`openScopes.last`). If no
    /// scope is open the registration is permanent until `remove(id:)` is
    /// called.
    @discardableResult
    package func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = nextID; nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        let target = activeScopeID ?? openScopes.last
        if let t = target {
            scopes[t]?.ids.append(id)
            handlerToScope[id] = t
        }
        return h
    }

    package func handler(forID id: Int) -> EventHandler? { handlers[id] }

    /// Removes a handler from the registry and from its owning scope.
    /// This keeps scope ID arrays compact across re-renders (handlers swapped
    /// out by `diffHandlers` are pruned immediately, not left as stale entries
    /// that accumulate until the component unmounts).
    package func remove(id: Int) {
        handlers.removeValue(forKey: id)
        if let scopeID = handlerToScope.removeValue(forKey: id) {
            scopes[scopeID]?.ids.removeAll { $0 == id }
        }
    }

    package func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

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
