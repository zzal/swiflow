// Sources/Swiflow/Reactivity/StateCell.swift
//
// Per-`@State` cell descriptor. Emitted by the `@Component` macro as
// `static let stateCells: [any AnyStateCell]`. The framework iterates
// this array to wire owners, take HMR snapshots, and apply HMR restores —
// replacing the Mirror-based walk that earlier framework versions used.
//
// Two-tier shape: `StateCell<Owner>` is generic so macro-emitted closures
// receive `Owner` directly (no `as!` casts in expanded code, which makes
// the expansion read like Swift a careful human would have written).
// The framework stores them as `[any AnyStateCell]` so it can iterate
// uniformly across component types; the single `as!` cast lives in the
// witness methods below.

/// Existential storage shape for `StateCell<Owner>`. Used by framework
/// code that iterates state cells without knowing the concrete owner type.
@MainActor
public protocol AnyStateCell {
    /// Field name as written by the user (e.g. `"count"` for
    /// `@State var count: Int = 0`). HMR snapshot/restore maps key by this.
    var name: String { get }

    /// Reads the current value from `owner` and returns it as `Any`.
    /// Caller is responsible for passing an `owner` of the right runtime
    /// type — a wrong type is a programmer error and traps via the
    /// `as!` cast inside the witness method.
    func snapshot(of owner: any Component) -> Any

    /// Attempts to write `value` into the cell on `owner`. Returns true
    /// on success, false on type mismatch (the framework logs a
    /// diagnostic and leaves the cell at its declared initial value).
    func restore(on owner: any Component, value: Any) -> Bool

    /// Restores the cell to `nil`. Returns false when `Value` is not
    /// Optional. Called by the HMR walker when the decoded state map
    /// contains an `HMRNilSentinel`.
    func restoreNil(on owner: any Component) -> Bool
}

/// Numeric coercion used by macro-emitted `StateCell` restore closures
/// to handle the JS bridge round-trip. `decodeStateMap` stores every
/// integral JS number as `Int` (so `@State var count: Int` round-trips
/// without loss), but that means an `@State var price: Double` whose
/// current value is `42.0` arrives here as `Int(42)`. Two coercion
/// branches cover both directions:
///   - `Int → Double` (and `Int → Double?`): most common.
///   - `Double → Int` (and `Double → Int?`): defensive; shouldn't arise
///     from `encodeStateMap` today, but guards future changes.
///
/// Public because macro-emitted code in user modules references it.
public func _hmrCoerce<T>(_ value: Any, to: T.Type) -> T? {
    // Fast path: exact type match (covers Bool, String, non-coerced
    // Int/Double, all Optional<T> where T matches exactly).
    if let typed = value as? T {
        return typed
    }
    // Int → Double (and Int → Double?). Swift conditionally casts
    // a non-Optional concrete value to an Optional destination by
    // wrapping in .some automatically.
    if let i = value as? Int, let typed = Double(i) as? T {
        return typed
    }
    // Double → Int (and Double → Int?). Only integral doubles qualify.
    if let d = value as? Double,
       d.truncatingRemainder(dividingBy: 1) == 0,
       let i = Int(exactly: d),
       let typed = i as? T {
        return typed
    }
    return nil
}

/// Type-safe `StateCell`. The macro emits these directly per `@State`
/// declaration, e.g. `StateCell<Counter>(name: "count", snapshot: { $0.count as Any }, ...)`.
@MainActor
public struct StateCell<Owner: Component>: AnyStateCell {
    public let name: String
    private let _snapshot: (Owner) -> Any
    private let _restore: (Owner, Any) -> Bool
    private let _restoreNil: (Owner) -> Bool

    public init(
        name: String,
        snapshot: @escaping (Owner) -> Any,
        restore: @escaping (Owner, Any) -> Bool,
        restoreNil: @escaping (Owner) -> Bool
    ) {
        self.name = name
        self._snapshot = snapshot
        self._restore = restore
        self._restoreNil = restoreNil
    }

    // Single cast site for the whole framework. Macro-emitted closures
    // never say `as! Counter` — they receive `Owner` directly.
    public func snapshot(of owner: any Component) -> Any {
        _snapshot(owner as! Owner)
    }
    public func restore(on owner: any Component, value: Any) -> Bool {
        _restore(owner as! Owner, value)
    }
    public func restoreNil(on owner: any Component) -> Bool {
        _restoreNil(owner as! Owner)
    }
}
