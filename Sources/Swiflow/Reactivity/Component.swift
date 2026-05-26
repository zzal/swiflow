// Sources/Swiflow/Reactivity/Component.swift

/// A reactive UI building block.
///
/// Components are reference-typed (class-bound) so that property mutations
/// — typically driven by `@State` — are visible to the framework without
/// the caller having to return a new value. Instances live across renders
/// when the parent's diff finds a same-position, same-type, same-key match;
/// the diff calls `body` again on the reused instance and reconciles the
/// result against the previously-mounted body subtree.
///
/// Conforming types should:
/// 1. Implement `var body: VNode` — pure, synchronous, runs every render.
/// 2. Optionally override `onAppear`, `onChange`, `onDisappear`.
/// 3. Declare reactive state with `@State` (Task 2) — direct stored
///    properties work but don't trigger re-renders.
@MainActor
public protocol Component: AnyObject {
    /// The view this component renders. Called by the diff on every render.
    /// Must be pure (no side effects) — the renderer doesn't memoize.
    var body: VNode { get }

    /// Called once after the component's body has been mounted to the DOM.
    /// Defaulted to no-op.
    func onAppear()

    /// Called after every re-render's patches have been applied. Use this
    /// hook to react to changes; the framework does NOT pass a snapshot of
    /// the prior state. Authors who need the prior value must stash it
    /// themselves before mutation (or via a side field).
    ///
    /// Defaulted to no-op.
    func onChange()

    /// Called immediately before the component's subtree is destroyed.
    /// Defaulted to no-op.
    func onDisappear()

    static var scopedStyles: CSSSheet? { get }
    static var exitAnimation: String? { get }
    static var exitDuration: Double? { get }
}

public extension Component {
    func onAppear() {}
    func onChange() {}
    func onDisappear() {}
    static var scopedStyles: CSSSheet? { nil }
    static var exitAnimation: String? { nil }
    static var exitDuration: Double? { nil }
}

/// Framework-runtime adoption point for `@Component`-decorated classes.
/// The macro emits the conformance + members. Hand-rolled `Component`
/// implementations (test mocks, stubs) can skip it — they just don't
/// get HMR wiring or state-cell dispatch, which is the right default
/// for code outside the macro's contract.
///
/// The leading underscore on the protocol name carries the
/// framework-internal signal once for the whole surface; members inside
/// have clean, unprefixed names.
@MainActor
public protocol _ComponentRuntime: Component {
    /// Descriptors for each `@State` cell on this type. Macro-emitted.
    static var stateCells: [any AnyStateCell] { get }

    /// Installs the owner + scheduler refs the synthesized `didSet`
    /// blocks call into. One call per instance per mount, not one per
    /// state cell. Macro-emitted.
    func bind(owner: AnyComponent, scheduler: Scheduler)
}

/// Type-erased reference to a `Component`. Stored on `MountNode` so the
/// mount tree can hold heterogeneous component instances without
/// conditional-conformance gymnastics. `typeID` is the identity used by the
/// diff to decide instance reuse.
public final class AnyComponent {
    /// `ObjectIdentifier(C.self)` for the concrete component type — not
    /// `ObjectIdentifier(instance)`. The diff uses this to decide whether
    /// the next render's component at the same position reuses this
    /// instance or replaces it (see `ComponentDescription`'s `==`).
    package let typeID: ObjectIdentifier

    /// The live component instance. Typed as the existential `any Component`
    /// so a mount tree can hold heterogeneous components in the same field.
    package let instance: any Component

    /// Wraps `instance` while capturing its concrete type as `typeID`.
    public init<C: Component>(_ instance: C) {
        self.typeID = ObjectIdentifier(C.self)
        self.instance = instance
    }
}

/// A value-typed factory description, used as the payload of
/// `VNode.component`. The diff compares descriptions by `typeID` + `key`;
/// two descriptions of the same component type at the same position are
/// considered the same and the existing instance is reused.
///
/// The `factory` closure isn't part of equality — closures aren't
/// equatable, and the factory is only consumed at first mount. Subsequent
/// renders with the same typeID + key reuse the existing AnyComponent.
///
/// **Sendable:** `ComponentDescription` is intentionally not `Sendable` in
/// Phase 3. It transitively holds a `() -> AnyComponent` factory whose
/// closure captures are unaudited. Components themselves aren't Sendable
/// either; the renderer/Scheduler are `@MainActor`-isolated, so factories
/// are only invoked on the main actor. Tightening `factory` to `@Sendable`
/// is deferred until cross-actor component usage becomes a real ask.
public struct ComponentDescription: Equatable {
    let typeID: ObjectIdentifier
    public let key: String?
    let factory: () -> AnyComponent

    package init(typeID: ObjectIdentifier, key: String?, factory: @escaping () -> AnyComponent) {
        self.typeID = typeID
        self.key = key
        self.factory = factory
    }

    /// Convenience init for the common case: a concrete Component factory.
    public init<C: Component>(_ type: C.Type, key: String? = nil, factory: @escaping () -> C) {
        self.typeID = ObjectIdentifier(type)
        self.key = key
        self.factory = { AnyComponent(factory()) }
    }

    /// Invokes the factory and returns a fresh `AnyComponent`. Each call
    /// produces a new instance; the diff is responsible for deciding
    /// when to call this (only at first mount, then never again for the
    /// same description-position pair).
    public func instantiate() -> AnyComponent {
        factory()
    }

    public static func == (lhs: ComponentDescription, rhs: ComponentDescription) -> Bool {
        lhs.typeID == rhs.typeID && lhs.key == rhs.key
    }
}

/// Wires the owner/scheduler refs into every `@State`-bearing
/// `@Component` so its `didSet` blocks can call
/// `scheduler.markDirty(owner)`.
///
/// Called by the diff at first mount of each component anchor.
/// No-op when `scheduler` is nil (used by tests and headless diffing).
///
/// Phase 15: drives wiring through `_ComponentRuntime.bind(...)`,
/// which the `@Component` macro emits. Hand-rolled `Component`
/// conformances that don't adopt `_ComponentRuntime` simply receive
/// no wiring — the right default, since they have no macro-emitted
/// `@State` cells to wire.
@MainActor
package func wireState(on owner: AnyComponent, scheduler: Scheduler?) {
    wireStateAndRestore(on: owner, scheduler: scheduler, stateMap: nil)
}

/// Fused owner-wiring + HMR restore. Iterates the
/// `_ComponentRuntime.stateCells` array emitted by the `@Component`
/// macro to wire `(owner, scheduler)` and apply pending snapshot
/// values in a single pass.
///
/// Called from the diff at component mount time (replaces the old
/// `wireState(on:scheduler:)` + `HMRRestoreInstall.restore?` pair).
/// `stateMap` is nil when no HMR swap is pending; wiring still
/// happens, restore is skipped.
///
/// State fields whose decoded value is `HMRNilSentinel` are routed to
/// the cell's `restoreNil` closure instead of `restore(value:)` — this
/// covers the JS-bridge path where `Optional.none` becomes JS `null`
/// then back.
@MainActor
func wireStateAndRestore(
    on owner: AnyComponent,
    scheduler: Scheduler?,
    stateMap: [String: Any]?,
    path: String = ""
) {
    guard scheduler != nil || stateMap != nil else { return }
    guard let runtime = owner.instance as? any _ComponentRuntime else { return }

    if let scheduler {
        runtime.bind(owner: owner, scheduler: scheduler)
    }

    guard let stateMap else { return }
    let cells = type(of: runtime).stateCells
    for cell in cells {
        guard let newValue = stateMap[cell.name] else { continue }
        let ok = newValue is HMRNilSentinel
            ? cell.restoreNil(on: runtime)
            : cell.restore(on: runtime, value: newValue)
        if !ok {
            let typeName = String(reflecting: type(of: runtime))
            swiflowDiagnostic(
                "HMR restore: type mismatch on \(typeName).\(cell.name) at path '\(path)'. Field reset to its declared initial value."
            )
        }
    }
}
