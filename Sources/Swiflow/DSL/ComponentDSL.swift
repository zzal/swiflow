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

/// Embeds a `Component` and pushes changed props into the **reused** instance
/// on every re-render, via the trailing `refresh:` closure.
///
/// Without `refresh:`, a changed prop never reaches a live embedded instance —
/// the factory runs only at first mount, so parents are forced to re-key
/// (`embed("row-\(value)") { … }`) to see the new value, which **remounts** the
/// child and resets its `@State`. `refresh:` is the additive fix: keep a stable
/// key, and re-push the parent's current data into the surviving instance right
/// before its `body` re-evaluates.
///
/// ```swift
/// embed("card-\(city.id)") {
///     CityCard(city: city, unit: self.unit)   // first mount only
/// } refresh: { card in
///     card.unit = self.unit                    // every re-render, same instance
/// }
/// ```
///
/// > ⚠️ **Target plain stored `var`s ONLY — never `@State`.** `@State` is
/// > framework-owned: assigning it fires the scheduler, and doing so from
/// > `refresh` re-enters the render loop on every frame → a hang. To change
/// > what a child renders from parent data, give it a plain `var` prop and push
/// > it here. (The factory contract from `embed(_:)` still applies to the
/// > factory closure: allocate a fresh instance per call.)
public func embed<C: Component>(
    _ factory: @escaping () -> C,
    refresh: @escaping (C) -> Void
) -> VNode {
    .component(ComponentDescription(C.self, key: nil, factory: factory, refresh: refresh))
}

/// Keyed variant of `embed(_:refresh:)`. `key` stabilizes identity across
/// reorders; `refresh` re-pushes props into the reused instance. Same
/// plain-`var`-not-`@State` contract as the unkeyed overload.
public func embed<C: Component>(
    _ key: String,
    _ factory: @escaping () -> C,
    refresh: @escaping (C) -> Void
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory, refresh: refresh))
}
