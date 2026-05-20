// Sources/Swiflow/DSL/ComponentDSL.swift

/// Embeds a `Component` in a VNode tree.
///
/// Usage in a parent component's body:
/// ```swift
/// div {
///     h1("Header")
///     embed { Counter() }              // unkeyed
///     embed("row-\(id)") { Row(id) }   // keyed; survives reorder
/// }
/// ```
///
/// The `factory` closure is invoked at first mount only. Subsequent renders
/// that produce an equal `ComponentDescription` at the same child position
/// reuse the existing instance (so `@State` survives re-renders) — see
/// `ComponentDescription` for the typeID+key identity rules.
///
/// - Warning: The factory closure must allocate a **fresh** instance every
///   call — `{ Counter() }`, not `{ self.existingCounter }`. Passing an
///   existing instance defeats the per-position reuse logic and produces
///   undefined `@State` lifecycle behaviour: the Mirror-based owner wiring
///   runs against whatever component the framework instantiates here, not
///   whatever instance the closure happens to return on a subsequent call.
public func embed<C: Component>(
    _ factory: @escaping () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: nil, factory: factory))
}

/// Embeds a keyed `Component` in a VNode tree. The `key` stabilizes identity
/// across reorders — see the unkeyed overload's doc for the warning about
/// fresh instances.
public func embed<C: Component>(
    _ key: String,
    _ factory: @escaping () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory))
}
