// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// The DSL calls `register(_:)` whenever a `.on("click") { … }` modifier is
/// applied. The diff engine then surfaces the handler ID inside a
/// `Patch.addHandler(…, handlerId:)` so the JS driver can route DOM events
/// back through a single Swift entry point (`dispatch(id:event:)`) per the
/// Swiflow refined spec § 4.1 and Branch 9.
///
/// Phase 1 ships storage + dispatch. Phase 2 wires the JS-side global
/// dispatcher to call into `dispatch(id:event:)` via JavaScriptKit.
public final class HandlerRegistry {
    private var nextID: Int = 0
    private var handlers: [Int: EventHandler] = [:]

    public init() {}

    /// Registers a closure and returns the `EventHandler` value to embed in
    /// an `ElementData.handlers` dictionary.
    @discardableResult
    public func register(_ invoke: @escaping (Event) -> Void) -> EventHandler {
        let id = nextID
        nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        return h
    }

    /// Returns the registered handler for an ID, or `nil` if absent (already
    /// removed or never registered).
    public func handler(forID id: Int) -> EventHandler? {
        handlers[id]
    }

    /// Drops the handler entry. A no-op for unknown IDs.
    public func remove(id: Int) {
        handlers.removeValue(forKey: id)
    }

    /// Invokes the closure registered under `id` with the given event.
    /// A no-op for unknown IDs (e.g., a stale event fired after unmount).
    public func dispatch(id: Int, event: Event) {
        handlers[id]?.invoke(event)
    }
}
