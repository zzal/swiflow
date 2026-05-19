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
    private var _owner: AnyComponent?
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
    /// Mirror walk). Idempotent in shape; redundant calls overwrite the
    /// previous owner — but in practice it's invoked exactly once per
    /// `@State` per Component instance, immediately after the
    /// component's `init` completes and before any render.
    ///
    /// Public-with-`_`-prefix so Mirror introspection (which can only
    /// reach `public` members from another module) can find and call
    /// it. The `_` flags it as framework-internal — user code should
    /// never invoke this directly.
    public func _setOwner(_ owner: AnyComponent, scheduler: Scheduler) {
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

// MARK: - Temporary Scheduler protocol stub
//
// The canonical definition lands in Task 6 at
// `Sources/Swiflow/Reactivity/Scheduler.swift`. This stub keeps Task 2
// self-contained: tests reference `Scheduler` (above), and the wrapper's
// `_setOwner` signature uses it.
//
// **TASK 6 IMPLEMENTER ACTION:** Delete the block below (the `#if`,
// the protocol declaration, and the `#endif`) when you land the
// canonical Scheduler.swift. The guard flag is never defined; the
// `#if !SWIFLOW_SCHEDULER_DEFINED_ELSEWHERE` is purely a grep-target
// to make this block easy to locate.
#if !SWIFLOW_SCHEDULER_DEFINED_ELSEWHERE
public protocol Scheduler: AnyObject {
    func markDirty(_ component: AnyComponent)
    func flush()
}
#endif
