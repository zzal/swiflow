// Sources/SwiflowWeb/SwiflowWeb.swift
//
// SwiflowWeb is the WASM-only renderer layer for Swiflow. All public API
// lives behind a `#if canImport(JavaScriptKit)` so the target compiles
// (empty) on platforms without WASM support — this lets `swift build` and
// `swift test` work on macOS/Linux developer machines while CI's WASM job
// builds the real symbols.

#if canImport(JavaScriptKit)
import JavaScriptKit
@_exported import Swiflow

// `Swiflow` namespace is declared here (Phase 1 deleted the core placeholder).
// The extension below hangs the renderer API off this enum.
public enum Swiflow {}

// Module-internal ambient renderer — single root per app in Phase 2a.
// `internal` (not `private`) so AttributeModifiers.swift can reach it
// when registering handlers during a render cycle.
nonisolated(unsafe) var ambientRenderer: Renderer?

public extension Swiflow {
    /// Mounts `viewProducer()` into the DOM node matched by `selector`.
    ///
    /// Subsequent calls to `Swiflow.rerender()` will re-evaluate the producer,
    /// diff against the committed tree, and ship the patches in one bridge
    /// call. **Phase 2a supports a single root per app.** Calling `render`
    /// twice traps with a clear error — `DispatcherBridge` captures the
    /// FIRST registry it sees, so a second `render` would silently break
    /// event dispatch for all subsequently registered handlers (they would
    /// land in a registry the bridge never reads). Phase 3's component
    /// lifecycle will replace this limitation.
    @MainActor
    static func render(_ viewProducer: @escaping () -> VNode, into selector: String) {
        precondition(
            ambientRenderer == nil,
            "Swiflow.render(_:into:) was already called. Phase 2a supports a single root per app; " +
            "a second render would silently drop event dispatch for new handlers because the JS " +
            "dispatcher remains bound to the first registry. Multi-root support arrives with " +
            "Phase 3's component lifecycle."
        )
        let renderer = Renderer(viewProducer: viewProducer, selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }

    /// Re-evaluates the registered view producer and applies any resulting
    /// patches. A no-op if `render(_:into:)` has not been called.
    @MainActor
    static func rerender() {
        ambientRenderer?.renderOnce()
    }

    /// Phase 3 entry point: mounts a `Component` root into the DOM node
    /// matched by `selector`.
    ///
    /// A `RAFScheduler` is created and wired into the diff so `@State`
    /// mutations on any component in the tree automatically schedule
    /// re-renders via `requestAnimationFrame`. No manual `rerender()` call
    /// is required.
    ///
    /// **Single-root:** same restriction as the Phase 2a overload — calling
    /// `render` twice traps. Multi-root support is a Phase 4 item.
    ///
    /// Usage:
    /// ```swift
    /// Swiflow.render(Counter(), into: "#app")
    /// ```
    @MainActor
    static func render<C: Component>(_ root: C, into selector: String) {
        precondition(
            ambientRenderer == nil,
            "Swiflow.render was already called. Phase 3 v1 supports a single root per app; " +
            "a second render would silently drop event dispatch for new handlers because the JS " +
            "dispatcher remains bound to the first registry."
        )
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }

}

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
