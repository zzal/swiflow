// Sources/Swiflow/Reactivity/State.swift

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

/// Two-way binding shaped like SwiftUI's. Used as the `projectedValue` of
/// `@State`, accessed via the `$`-prefix sigil:
///
/// ```swift
/// @State var text = ""
/// // ...
/// input(.value($text))   // pass the binding
/// ```
///
/// Phase 3 v1 doesn't yet have any DSL bindings that consume `Binding`;
/// it's surfaced now so the API is set in stone before Phase 4's form
/// helpers land. Until then, callers can use it manually via `get`/`set`.
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
