// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// Scoped: callers open a named scope before invoking `body`; all IDs
/// registered while a scope is open are tracked against that scope.
/// Closing the scope evicts every ID registered inside it, ensuring
/// `.on(_:perform:)` closures cannot outlive their owning Component instance.
///
/// Scopes are identified by stable integer IDs returned from `openScope()`.
/// `closeScope(id:)` evicts by ID, not by stack position, so sibling
/// components can be destroyed in any order without cross-contamination.
///
/// `package` access: visible to `SwiflowWeb` (same package) but not to
/// application code that imports Swiflow as a library dependency.
package final class HandlerRegistry: @unchecked Sendable {
    private var nextID: Int = 0
    private var nextFrameID: Int = 0
    private var handlers: [Int: EventHandler] = [:]

    private struct Frame {
        var name: String
        var ids: [Int]
    }
    private var frames: [Int: Frame] = [:]
    private var frameStack: [Int] = []       // open frame IDs in push order; last = top
    private var handlerToFrame: [Int: Int] = [:]  // handlerID → frameID for O(1) removal
    private var activeFrameID: Int? = nil    // set during withScope(id:_:)

    package init() {}

    // MARK: - Scope management

    /// Opens a new scope frame and returns its stable ID. The ID must be
    /// saved and passed to `closeScope(id:)` at unmount time.
    package func openScope(name: String = "") -> Int {
        let id = nextFrameID; nextFrameID += 1
        frames[id] = Frame(name: name, ids: [])
        frameStack.append(id)
        return id
    }

    /// Closes the scope identified by `id`, evicting every handler it owns
    /// from the registry. Safe to call in any order relative to other open
    /// scopes — lookup is by stable frame ID, not by stack position.
    package func closeScope(id: Int) {
        guard let frame = frames.removeValue(forKey: id) else { return }
        frameStack.removeAll { $0 == id }
        for hid in frame.ids {
            handlers.removeValue(forKey: hid)
            handlerToFrame.removeValue(forKey: hid)
        }
    }

    /// Runs `body` with `id` as the active scope frame. Handlers registered
    /// during `body` are tracked against frame `id`, regardless of what
    /// frames are currently on top of the open-frame stack. Saves and
    /// restores the previous active frame, so nested calls compose correctly.
    ///
    /// Use this around every component `body` evaluation during both mount
    /// and update so handler ownership is always correct — even when sibling
    /// or descendant scopes are simultaneously open.
    @discardableResult
    package func withScope<T>(id: Int, _ body: () -> T) -> T {
        let previous = activeFrameID
        activeFrameID = id
        defer { activeFrameID = previous }
        return body()
    }

    /// Variant of `withScope(id:_:)` that is a no-op when `id` is `nil`.
    /// Allows callers to pass an optional scope ID without extra unwrapping
    /// when a non-component node has no associated scope.
    @discardableResult
    package func withScope<T>(id: Int?, _ body: () -> T) -> T {
        guard let id else { return body() }
        return withScope(id: id, body)
    }

    // MARK: - Handler management

    /// Registers a closure and returns the `EventHandler`. Tracks the ID
    /// against `activeFrameID` when set (inside `withScope`), otherwise
    /// against the most-recently-opened frame (`frameStack.last`). If no
    /// scope is open the registration is permanent until `remove(id:)` is
    /// called.
    @discardableResult
    package func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = nextID; nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        let target = activeFrameID ?? frameStack.last
        if let t = target {
            frames[t]?.ids.append(id)
            handlerToFrame[id] = t
        }
        return h
    }

    package func handler(forID id: Int) -> EventHandler? { handlers[id] }

    /// Removes a handler from the registry and from its owning scope frame.
    /// This keeps frame ID arrays compact across re-renders (handlers swapped
    /// out by `diffHandlers` are pruned immediately, not left as stale entries
    /// that accumulate until the component unmounts).
    package func remove(id: Int) {
        handlers.removeValue(forKey: id)
        if let frameID = handlerToFrame.removeValue(forKey: id) {
            frames[frameID]?.ids.removeAll { $0 == id }
        }
    }

    package func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

    // MARK: - Diagnostics

    /// Returns handler counts per scope name. Used by `__swiflow__.handlers()`.
    package func countPerScope() -> [String: Int] {
        var result: [String: Int] = [:]
        for (_, frame) in frames {
            result[frame.name, default: 0] += frame.ids.count
        }
        return result
    }
}
