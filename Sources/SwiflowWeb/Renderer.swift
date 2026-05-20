// Sources/SwiflowWeb/Renderer.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Owns Swiflow's per-application render state in a WASM/browser environment.
///
/// A single Renderer is created by `Swiflow.render(_:into:)` and looked up by
/// `Swiflow.rerender()` through module-private ambient storage. Multiple
/// roots are out of scope for Phase 2a / Phase 3 v1.
///
/// Two initialization modes:
///
/// - **Phase 2a (viewProducer):** `init(viewProducer:selector:)` — caller
///   supplies a `() -> VNode` closure evaluated on every render. No scheduler
///   is created; `Swiflow.rerender()` drives re-renders manually.
///
/// - **Phase 3 (Component root):** `init(rootComponent:selector:)` — caller
///   supplies an `AnyComponent` instance. A `RAFScheduler` is created and
///   wired into the diff so `@State` mutations automatically schedule re-renders
///   via `requestAnimationFrame`. Manual `rerender()` calls are not needed.
@MainActor
final class Renderer {
    // MARK: - Stored properties

    /// Non-nil only for the Phase 2a (viewProducer) init. Exactly one of
    /// `viewProducer` and `rootComponent` is non-nil at any given time.
    let viewProducer: (() -> VNode)?

    /// Non-nil only for the Phase 3 (Component root) init.
    let rootComponent: AnyComponent?

    /// The CSS selector the JS driver uses to attach the root DOM node.
    let selector: String

    /// Allocates monotonically-increasing integer handles for new DOM nodes.
    let handles: HandleAllocator

    /// Stores event-handler closures by ID; wired into the JS dispatcher.
    let handlers: HandlerRegistry

    /// The committed mount tree from the last `renderOnce()`, or `nil` before
    /// the first render.
    var mountTree: MountNode?

    /// Cumulative count of `renderOnce()` calls since this Renderer was created.
    /// Read by `DevAPI` to populate `__swiflow.perf().renders`.
    private(set) var renderCount: Int = 0

    /// Count of patches emitted by the most recent `renderOnce()` call.
    /// Read by `DevAPI` to populate `__swiflow.perf().lastPatchCount`.
    private(set) var lastPatchCount: Int = 0

    /// Wall-clock duration of the most recent `renderOnce()` call, in milliseconds.
    /// Measured via `window.performance.now()`. Read by `DevAPI` to populate
    /// `__swiflow.perf().lastRenderMs`.
    private(set) var lastRenderMs: Double = 0

    /// Heap-allocated cell that allows the Phase 3 init to assign the
    /// `RAFScheduler` after `self` is fully initialised — required because
    /// the scheduler closure needs a weak reference to `self`, which can only
    /// be formed once all stored properties are set.
    ///
    /// Phase 2a init leaves this at its default `nil`. Phase 3 init assigns
    /// the scheduler to `_schedulerBox.value` in its body, after the
    /// two-phase initialisation constraint is satisfied.
    private let _schedulerBox: MutableBox<(any Scheduler)?> = MutableBox(nil)

    /// The active `Scheduler`, if any. Non-nil only for Phase 3 renderers.
    /// Exposed as a computed property so tests and internal callers get
    /// a clean `Scheduler?` type without reaching into the box.
    var scheduler: (any Scheduler)? { _schedulerBox.value }

    // MARK: - Initializers

    /// Phase 2a init: the renderer evaluates `viewProducer` on every render.
    /// No scheduler is created — re-renders are triggered manually via
    /// `Swiflow.rerender()`.
    init(viewProducer: @escaping () -> VNode, selector: String) {
        self.viewProducer = viewProducer
        self.rootComponent = nil
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil
        // _schedulerBox stays nil (default).
    }

    /// Phase 3 init: the renderer wraps a live Component instance and wires
    /// a `RAFScheduler` so `@State` mutations automatically schedule
    /// re-renders without any manual `rerender()` call.
    ///
    /// The `RAFScheduler` captures `self` weakly to avoid a retain cycle:
    /// Renderer → _schedulerBox → RAFScheduler → closure → Renderer.
    init(rootComponent: AnyComponent, selector: String) {
        self.viewProducer = nil
        self.rootComponent = rootComponent
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil
        // _schedulerBox is default-initialised to nil above (let constant
        // with a default value). At this point all stored properties are
        // set and `self` is fully initialised — safe to form a weak capture.
        let raf = RAFScheduler { [weak self] in
            self?.renderOnce()
        }
        _schedulerBox.value = raf
    }

    // MARK: - Render

    /// Runs the view producer or re-renders the root component, diffs against
    /// the current mount tree, encodes patches into a JSArray, hands the array
    /// to `window.swiflow.applyPatches`, and — on first call — tells the
    /// driver to attach the root node at `selector`. Also fires lifecycle
    /// hooks on the root component when applicable.
    func renderOnce() {
        let nextVNode: VNode

        if let producer = viewProducer {
            // Phase 2a: evaluate the producer closure.
            nextVNode = producer()
        } else if let root = rootComponent {
            // Phase 3: wrap the existing component instance in a VNode.component
            // description whose factory returns THE SAME instance rather than
            // constructing a fresh one. This is critical for the diff's reuse
            // arm (`.component`/`.component` case in `update()`): on first
            // render `desc.instantiate()` is called once in `mount()`, yielding
            // the already-live instance; on subsequent renders the diff's
            // same-typeID path reuses the mount-tree node and calls `body` on
            // the existing instance — the factory is never called again.
            let desc = ComponentDescription(
                typeID: root.typeID,
                key: nil,
                factory: { root }
            )
            nextVNode = .component(desc)
        } else {
            preconditionFailure(
                "Renderer has neither a viewProducer nor a rootComponent. " +
                "This indicates a programming error in Renderer's init — " +
                "exactly one of the two must be non-nil."
            )
        }

        let renderStartMs = JSObject.global.performance.now().number ?? 0
        let result = diff(
            mounted: mountTree,
            next: nextVNode,
            handles: handles,
            handlers: handlers,
            scheduler: _schedulerBox.value
        )
        lastPatchCount = result.patches.count
        renderCount += 1
        lastRenderMs = (JSObject.global.performance.now().number ?? 0) - renderStartMs

        // Encode patches to a JSArray and ship across the bridge.
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in result.patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }

        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // Use domHandle (not handle): for a Component-root tree, the mount
            // tree root is the component anchor whose `handle` is structural-
            // only (the driver never saw a create* patch for it). The body's
            // DOM handle is what the driver needs to attach at `selector`.
            // For a viewProducer tree, domHandle == handle (no anchor layer),
            // so this is correct in both modes.
            let mountHandle = result.newMountTree.domHandle
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(mountHandle)),
                JSValue.string(selector)
            )
            // Lifecycle: fire onAppear on the root component after patches
            // have been shipped to the driver (DOM is now live).
            if let root = rootComponent {
                root.instance.onAppear()
            }
        } else {
            // Lifecycle: fire onChange on the root component.
            if let root = rootComponent {
                root.instance.onChange()
            }
        }
    }
}

// MARK: - Mutable box for two-phase scheduler init

/// Heap-allocated mutable cell. Used by `Renderer` to store the `RAFScheduler`
/// after `self` is fully initialised, working around Swift's `let` stored
/// property constraint in two-phase initialisation. This is the same pattern
/// as `State<T>`'s `Box<T>` in the core module.
private final class MutableBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

#endif
