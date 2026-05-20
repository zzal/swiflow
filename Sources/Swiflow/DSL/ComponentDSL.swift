// Sources/Swiflow/DSL/ComponentDSL.swift

/// Embeds a `Component` in a VNode tree.
///
/// > ⚠️ **Factory contract:** the `factory` closure MUST allocate a fresh
/// > instance on every call — write `{ Counter() }`, never
/// > `{ self.existingCounter }`. Returning a previously-mounted instance
/// > corrupts `@State` lifecycle: the Mirror-based owner wiring re-runs
/// > against the framework's idea of "this slot's component", not the
/// > instance the closure happens to return. DEBUG builds catch this
/// > with a `swiflowDiagnostic`.
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
/// The framework invokes `factory` only on first mount of a given
/// `(typeID, key)` position. Subsequent renders at the same position
/// reuse the existing instance — that's how `@State` survives re-renders.
/// See `ComponentDescription` for the typeID+key identity rules.
public func embed<C: Component>(
    _ factory: @escaping () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: nil, factory: factory))
}

/// Embeds a keyed `Component` in a VNode tree. The `key` stabilizes
/// identity across reorders. The same factory contract from
/// `embed(_:)`'s leading ⚠️ block applies: allocate a fresh instance
/// per call.
public func embed<C: Component>(
    _ key: String,
    _ factory: @escaping () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory))
}
