// Sources/Swiflow/Reactivity/Ref.swift

/// A first-party DOM reference, populated by the framework at element
/// mount time. Use to focus an input, scroll an element into view, or
/// invoke any other imperative DOM API.
///
/// ```swift
/// final class Form: Component {
///     let nameInput = Ref<JSObject>()
///     @State var name = ""
///
///     var body: VNode {
///         input(.value($name), .ref(nameInput))
///     }
///
///     func onAppear() {
///         if let el = nameInput.wrappedValue { _ = el.focus!() }
///     }
/// }
/// ```
///
/// `wrappedValue` returns `nil` outside the mount window (before
/// `onAppear` fires; after `onDisappear` returns).
///
/// Phase 7 ships only `Ref<JSObject>` end-to-end (the canonical shape).
/// `Element` is generic so future typed wrappers (`Ref<HTMLInputElement>`)
/// can land without an ABI break, but Phase 7 only resolves to
/// `JSObject` via the platform-side resolver installed by SwiflowDOM.
///
/// **Sendable:** `Ref` is intentionally not `Sendable`. It mutates from
/// the `@MainActor`-isolated diff and is read by user code running on
/// the main actor (e.g. `onAppear`). Ref instances are owned by their
/// Component and never cross isolation boundaries.
@MainActor
public final class Ref<Element> {
    /// Framework-set integer handle into the JS driver's node map. Opaque
    /// to user code — use `wrappedValue` to get at the live DOM node.
    /// `package` so `AnyRefBinding` (same module) can write through it.
    package var handle: Int?

    public init() {}

    /// Looks the bound DOM node up in the JS-side handle table. Returns
    /// `nil` if the ref isn't currently bound (before mount, after
    /// unmount), the JS driver isn't loaded, or the framework hasn't
    /// installed the resolver yet.
    public var wrappedValue: Element? {
        guard let handle = handle else { return nil }
        return RefResolverInstall.resolver?(handle) as? Element
    }

    /// `$ref` projected value used by the `.ref(_:)` modifier. Returns
    /// `self` — the convention mirrors SwiftUI's `$state` shape.
    public var projectedValue: Ref<Element> { self }
}

/// Type-erased binding written to `ElementData.refBindings`. Diff mounts
/// call `setHandle` with the freshly allocated DOM-node handle; destroy
/// calls `clearHandle`. The closures capture the underlying `Ref<E>`
/// strongly so the binding stays valid for the element's lifetime —
/// the `Ref` is owned by the user's Component, which outlives the
/// VNode tree.
///
/// Type-erased because Diff has no business knowing the Ref's `Element`
/// generic parameter; it just needs the two lifecycle hooks.
///
/// **Equatable / Sendable:** intentionally neither. The closures aren't
/// Equatable, and AnyRefBinding inherits the non-Sendable status of
/// `ElementData` itself (see VNode.swift's Sendable note — same reasoning
/// as `EventHandler`).
public struct AnyRefBinding {
    /// Called by Diff at element mount, after the handle is allocated
    /// and before child mounts. Writes `handle` into the underlying Ref.
    package let setHandle: @MainActor (Int) -> Void
    /// Called by Diff at element destroy. Nils out the underlying Ref's
    /// handle so post-unmount `wrappedValue` reads return nil.
    package let clearHandle: @MainActor () -> Void

    /// Wraps a typed `Ref<E>` as an erased binding. The closures retain
    /// `ref` so the binding's mount/destroy hooks remain valid for the
    /// element's lifetime regardless of where the Ref is stored.
    public init<E>(_ ref: Ref<E>) {
        self.setHandle = { ref.handle = $0 }
        self.clearHandle = { ref.handle = nil }
    }
}

/// Non-generic shim that holds the platform-side resolver closure
/// (installed by `SwiflowDOM.Swiflow.render(into:_:)`). The resolver
/// maps an integer handle to the live JS DOM node via
/// `window.swiflow.nodeForHandle(h)`.
///
/// **Why a non-generic shim?** A static stored var on `Ref<Element>`
/// is keyed per generic specialization — `Ref<JSObject>._resolver` and
/// `Ref<HTMLInputElement>._resolver` would be independent slots. The
/// resolver isn't type-specific (it always produces a JS DOM node),
/// so it lives on a non-generic side type and is shared by every
/// `Ref<E>` instance.
///
/// **Thread isolation:** `nonisolated(unsafe)` mirrors the pattern used
/// by `URLSanitizer.allowedSchemes` and `ambientRenderer`. The resolver
/// is written exactly once at `render(into:_:)` time on the main actor
/// and read on the main actor; the cross-actor risk is nil in practice.
public enum RefResolverInstall {
    /// Resolves a Swiflow handle to a platform-specific DOM node. Set
    /// by `Swiflow.render(into:_:)` and read by `Ref.wrappedValue`.
    /// The return type is `Any?` because the resolver lives in the
    /// platform-agnostic Swiflow module; SwiflowDOM installs a closure
    /// returning `JSObject?` (wrapped as `Any?` for storage). User code
    /// goes through `Ref<E>.wrappedValue`, which does the `as? E` cast.
    nonisolated(unsafe) public static var resolver: (@MainActor (Int) -> Any?)?
}
