// Sources/Swiflow/Reactivity/State.swift

/// Internal protocol witness for Mirror-based @State discovery. Lets the
/// framework cast `Mirror.children`'s `Any` values to a known shape with
/// the wire-owner method. `State` conforms via the extension below.
///
/// Kept package-internal — the only caller is `wireState(on:scheduler:)`
/// in `Component.swift`. User code should not see this protocol.
protocol StateWireable: AnyObject {
    func _setOwner(_ owner: AnyComponent, scheduler: Scheduler)

    /// HMR snapshot: returns the current `wrappedValue` typed as `Any`.
    /// The HMRWalker inspects the runtime type to decide whether the
    /// value belongs in the snapshot's supported-primitive set
    /// (String/Int/Double/Bool + Optionals).
    func _hmrSnapshotValue() -> Any

    /// HMR restore: if `newValue` is type-compatible with `Value`,
    /// overwrites the storage. Returns true on success, false on
    /// type mismatch. Called at most once per @State, after Component
    /// instantiation but before the first `body` evaluation, so no
    /// scheduler notification is needed.
    func _hmrRestore(_ newValue: Any) -> Bool

    /// HMR nil restore: sets the storage to `Optional.none`. Only
    /// meaningful for `@State var foo: T?`; returns false immediately
    /// for non-Optional `Value`. Called by `HMRWalker.applyRestore`
    /// when the decoded state map contains an `HMRNilSentinel` — the
    /// signal that this field was `nil` at snapshot time.
    func _hmrRestoreNil() -> Bool
}

/// Reactive state for a Component. Mutating `wrappedValue` flags the
/// owning component as dirty with the active Scheduler, which batches
/// re-renders per `requestAnimationFrame`.
///
/// Without an owner wired in, mutations are silent — useful for tests
/// constructing `@State` values outside a Renderer. The framework wires
/// the owner via `_setOwner(_:scheduler:)` at component-construction time
/// (Task 7's Mirror walk).
///
/// Usage:
/// ```swift
/// final class Counter: Component {
///     @State var count = 0
///     var body: VNode { p("\(count)") }
/// }
/// ```
///
/// **Sendable:** `State` is intentionally not `Sendable` in Phase 3. It
/// holds an `AnyComponent` owner reference and a closure-captured
/// `Scheduler`; both are confined to the `@MainActor`-isolated Renderer.
/// Tightening Sendable conformance waits on the same actor-model lock-in
/// as `Component` itself.
@propertyWrapper
public final class State<Value> {
    private let storage: Box<Value>
    // Optional so the framework can attach the owner post-construction
    // without circularity headaches. Set exactly once per @State per
    // component instance (Task 7's Mirror walk handles this).
    // Weak to break the retain cycle: Component owns @State (synthesized
    // stored property), State._owner would otherwise own AnyComponent,
    // and AnyComponent.instance owns the same Component back. Mirrors
    // the MountNode.parent precedent. When the Component is released
    // (Renderer drops the mount), _owner safely becomes nil and the
    // setter's `if let owner = _owner` short-circuits.
    private weak var _owner: AnyComponent?
    // Erased to `AnyObject` because storing a non-existential protocol
    // reference triggers Sendable diagnostics; we cast back to `Scheduler`
    // at use. The scheduler outlives any single @State by design (it's
    // owned by the Renderer), so a strong reference is acceptable.
    private var _scheduler: AnyObject?

    public init(wrappedValue: Value) {
        self.storage = Box(value: wrappedValue)
    }

    public var wrappedValue: Value {
        get { storage.value }
        set {
            storage.value = newValue
            if let owner = _owner, let scheduler = _scheduler as? Scheduler {
                scheduler.markDirty(owner)
            }
        }
    }

    /// The two-way binding for this state cell, accessed via the `$`
    /// sigil:
    ///
    /// ```swift
    /// @State var text = ""
    /// // ...
    /// input(.value($text))   // round-trips through `.input` events
    /// ```
    ///
    /// Consumers ship in `SwiflowWeb.AttributeModifiers`: `.value(_:)`
    /// for text inputs and textareas, `.checked(_:)` for checkboxes, and
    /// `.selection(_:)` for selects.
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.storage.value },
            set: { self.wrappedValue = $0 }
        )
    }

    /// Called by the framework at component-construction time (Task 7's
    /// Mirror walk). Must be called exactly once per `@State` per
    /// Component instance, immediately after the component's `init`
    /// completes and before any render. A second call traps via a
    /// `precondition` — it would indicate the wiring code re-ran when
    /// it shouldn't have.
    ///
    /// Public-with-`_`-prefix so Mirror introspection (which can only
    /// reach `public` members from another module) can find and call
    /// it. The `_` flags it as framework-internal — user code should
    /// never invoke this directly.
    public func _setOwner(_ owner: AnyComponent, scheduler: Scheduler) {
        precondition(
            _owner == nil,
            "_setOwner called twice on the same @State — Task 7's Mirror walk should invoke this exactly once per @State per Component instance. Investigate the call site (re-rendering shouldn't re-wire state)."
        )
        self._owner = owner
        self._scheduler = scheduler as AnyObject
    }
}

/// Two-way binding shaped like SwiftUI's. The projected value of
/// `@State`, accessed via the `$`-prefix sigil:
///
/// ```swift
/// @State var text = ""
/// @State var agreed = false
/// @State var choice = "A"
/// // ...
/// input(.value($text))         // .input event, text round-trip
/// input(.attr("type", "checkbox"), .checked($agreed))   // .change event
/// select(.selection($choice)) { option("A"); option("B") }
/// ```
///
/// Consumers ship in `SwiflowWeb.AttributeModifiers`: `.value(_:)`,
/// `.checked(_:)`, and `.selection(_:)` — all in both prefix
/// (`Attribute` static) and postfix (`VNode` method) shapes.
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}

/// Heap-allocated value cell. `@State` is a `class` (so the property
/// wrapper survives `let` declarations on the enclosing component), but
/// storing the value directly on the class would force a heap allocation
/// per assignment for value types. Boxing once at construction time and
/// mutating the box keeps allocation overhead constant.
final class Box<Value> {
    var value: Value
    init(value: Value) { self.value = value }
}

extension State {
    /// HMR snapshot extraction. See `StateWireable._hmrSnapshotValue()`.
    /// Public-with-`_`-prefix so Mirror introspection (which can only
    /// reach `public` members from another module) can find and call
    /// it. The `_` flags it as framework-internal — user code should
    /// never invoke this directly. Matches the `_setOwner` precedent
    /// above.
    public func _hmrSnapshotValueImpl() -> Any { storage.value }

    /// HMR restore. See `StateWireable._hmrRestore(_:)`. Returns false
    /// when `newValue` cannot be reconciled to `Value`.
    ///
    /// Numeric coercions handle the JS bridge round-trip: `decodeStateMap`
    /// stores every integral JS number as `Int` (so `@State var count: Int`
    /// round-trips without loss), but that means an `@State var price: Double`
    /// whose current value is `42.0` arrives here as `Int(42)`. Two coercion
    /// branches cover both directions:
    ///   - `Int → Double` (and `Int → Double?`): most common.
    ///   - `Double → Int` (and `Double → Int?`): defensive; shouldn't arise
    ///     from `encodeStateMap` today, but guards future changes.
    public func _hmrRestoreImpl(_ newValue: Any) -> Bool {
        // Fast path: exact type match (handles Bool, String, non-coerced
        // Int/Double, all Optional<T> where T matches exactly, and the
        // Swift-only nil-Optional sentinel `Optional<T>.none as Any`).
        if let typed = newValue as? Value {
            storage.value = typed
            return true
        }
        // Int → Double coercion. `Double(i) as? Value` covers both
        // `Value = Double` and `Value = Double?` in one branch: Swift's
        // runtime promotes `Double` to `Optional<Double>.some(_)` on
        // a conditional cast to an Optional destination.
        if let i = newValue as? Int, let typed = Double(i) as? Value {
            storage.value = typed
            return true
        }
        // Double → Int coercion. Only integral doubles qualify.
        if let d = newValue as? Double,
           d.truncatingRemainder(dividingBy: 1) == 0,
           let i = Int(exactly: d),
           let typed = i as? Value {
            storage.value = typed
            return true
        }
        return false
    }

}

extension State: StateWireable {
    public func _hmrSnapshotValue() -> Any { _hmrSnapshotValueImpl() }
    public func _hmrRestore(_ newValue: Any) -> Bool { _hmrRestoreImpl(newValue) }

    /// Restores this state cell to `Optional.none`. Uses existential
    /// metatype opening to detect and construct the nil value without
    /// conditional extensions — critical because protocol witness dispatch
    /// for class types resolves at a single generic `State<Value>` level
    /// and would silently select a conditional extension's base (false)
    /// for every `Value`, including Optional ones.
    ///
    /// Steps:
    ///  1. Cast `Value.self` to `any ExpressibleByNilLiteral.Type` — only
    ///     succeeds when `Value` is `Optional<T>` (or another nil-literal
    ///     type, which is exotic and safe to handle identically).
    ///  2. Call `.init(nilLiteral: ())` on the opened metatype to get the
    ///     concrete nil value (type-erased as `any ExpressibleByNilLiteral`).
    ///  3. Cast back to `Value` — always succeeds because the metatype's
    ///     dynamic type IS `Value.self`.
    public func _hmrRestoreNil() -> Bool {
        guard let nilLiteralType = Value.self as? any ExpressibleByNilLiteral.Type else {
            return false
        }
        let nilValue = nilLiteralType.init(nilLiteral: ())
        guard let typed = nilValue as? Value else { return false }
        storage.value = typed
        return true
    }
}
