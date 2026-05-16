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

// Module-private ambient renderer — single root per app in Phase 2a.
nonisolated(unsafe) private var ambientRenderer: Renderer?

public extension Swiflow {
    /// Mounts `viewProducer()` into the DOM node matched by `selector`.
    ///
    /// Subsequent calls to `Swiflow.rerender()` will re-evaluate the producer,
    /// diff against the committed tree, and ship the patches in one bridge
    /// call. Phase 2a supports a single root per app; calling `render` twice
    /// replaces the prior renderer (no cleanup — out of scope until Phase 3
    /// adds component lifecycle).
    static func render(_ viewProducer: @escaping () -> VNode, into selector: String) {
        let renderer = Renderer(viewProducer: viewProducer, selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }

    /// Re-evaluates the registered view producer and applies any resulting
    /// patches. A no-op if `render(_:into:)` has not been called.
    static func rerender() {
        ambientRenderer?.renderOnce()
    }

    /// The handler registry the active Renderer dispatches through.
    ///
    /// Use this inside `view()` to register `.on(...)` closures:
    ///
    /// ```swift
    /// button("Click", .on("click", Swiflow.handlers.register { _ in ... }))
    /// ```
    ///
    /// **Critical:** user closures MUST be registered via this property
    /// (not a private `HandlerRegistry` the user constructs themselves).
    /// `DispatcherBridge` routes every JS event to the Renderer's registry;
    /// handlers registered elsewhere will silently no-op when their event
    /// fires, AND will leak their closures because `diffHandlers`'s
    /// `handlers.remove(id:)` only affects the Renderer's registry.
    ///
    /// `Swiflow.render(_:into:)` must have been called before this property
    /// is accessed. Inside `view()` this is always safe — `render` constructs
    /// the Renderer and only THEN calls the producer.
    static var handlers: HandlerRegistry {
        guard let renderer = ambientRenderer else {
            fatalError("Swiflow.handlers accessed before Swiflow.render(_:into:) was called")
        }
        return renderer.handlers
    }
}

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
