// Sources/Swiflow/DSL/ComponentDSL.swift

/// Embeds a Component in a VNode tree.
///
/// Usage in a parent component's body:
/// ```swift
/// div {
///     h1("Header")
///     component({ Counter() })           // unkeyed
///     component({ Counter() }, key: "a") // keyed; survives reorder
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
///   (Task 7) runs against whatever component the framework instantiates
///   here, not whatever instance the closure happens to return on a
///   subsequent call.
///
/// **Naming:** the lowercase `component(_:key:)` function and the uppercase
/// `Component` protocol coexist via Swift's case-sensitive disambiguation.
/// Reading sites like `component({ Counter() })` make it clear which is which.
public func component<C: Component>(
    _ factory: @escaping () -> C,
    key: String? = nil
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory))
}
