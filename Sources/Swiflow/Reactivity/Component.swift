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
/// 2. Optionally override `onMount`, `onUpdate(prev:)`, `onUnmount`.
/// 3. Declare reactive state with `@State` (Task 2) — direct stored
///    properties work but don't trigger re-renders.
public protocol Component: AnyObject {
    /// The view this component renders. Called by the diff on every render.
    /// Must be pure (no side effects) — the renderer doesn't memoize.
    var body: VNode { get }

    /// Called once after the component's body has been mounted to the DOM.
    /// Defaulted to no-op.
    func onMount()

    /// Called after every re-render's patches have been applied.
    /// `prev` is the same instance (reference equality holds); the parameter
    /// exists for symmetry with React's `prevProps` signature. Defaulted
    /// to no-op.
    func onUpdate(prev: Self)

    /// Called immediately before the component's subtree is destroyed.
    /// Defaulted to no-op.
    func onUnmount()
}

public extension Component {
    func onMount() {}
    func onUpdate(prev: Self) {}
    func onUnmount() {}
}

/// Type-erased reference to a `Component`. Stored on `MountNode` so the
/// mount tree can hold heterogeneous component instances without
/// conditional-conformance gymnastics. `typeID` is the identity used by the
/// diff to decide instance reuse.
public final class AnyComponent {
    public let typeID: ObjectIdentifier
    public let instance: any Component

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
public struct ComponentDescription: Equatable {
    public let typeID: ObjectIdentifier
    public let key: String?
    public let factory: () -> AnyComponent

    public init(typeID: ObjectIdentifier, key: String?, factory: @escaping () -> AnyComponent) {
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

    public func instantiate() -> AnyComponent {
        factory()
    }

    public static func == (lhs: ComponentDescription, rhs: ComponentDescription) -> Bool {
        lhs.typeID == rhs.typeID && lhs.key == rhs.key
    }
}
