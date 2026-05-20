// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// Scoped: callers (the Renderer, on Component mount) open a scope before
/// invoking `body`; all IDs registered while a scope is open are tracked
/// against that scope. Closing the scope (on Component unmount) evicts
/// every ID registered inside it. This lets `.on(_:perform:)` closures
/// capture `self` strongly: the framework guarantees the closure is dead
/// before the Component instance is.
///
/// `package` access: visible to `SwiflowWeb` (same package) but not to
/// application code that imports Swiflow as a library dependency.
package final class HandlerRegistry {
    private var nextID: Int = 0
    private var handlers: [Int: EventHandler] = [:]
    private var scopeStack: [[Int]] = []     // each frame is the IDs registered in that scope
    private var scopeNames: [String] = []    // parallel array of scope names

    package init() {}

    /// Registers a closure and returns the `EventHandler`. If a scope is
    /// currently open, the ID is tracked against the innermost scope and
    /// will be evicted when that scope closes. If no scope is open, the
    /// registration is permanent until explicitly `remove(id:)`'d.
    @discardableResult
    package func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = nextID
        nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(id)
        }
        return h
    }

    package func handler(forID id: Int) -> EventHandler? { handlers[id] }
    package func remove(id: Int) { handlers.removeValue(forKey: id) }
    package func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

    package func openScope(name: String = "") {
        scopeStack.append([])
        scopeNames.append(name)
    }

    package func closeScope() {
        guard let ids = scopeStack.popLast() else { return }
        scopeNames.removeLast()
        for id in ids { handlers.removeValue(forKey: id) }
    }

    package func countPerScope() -> [String: Int] {
        var result: [String: Int] = [:]
        for (name, ids) in zip(scopeNames, scopeStack) {
            result[name, default: 0] += ids.count
        }
        return result
    }
}
