// Sources/SwiflowWeb/DispatcherBridge.swift
//
// STUB: T6 replaces the body of `installIfNeeded` with the real JS-side
// dispatcher wiring. Shipping the stub here lets Renderer.swift compile in
// T5 without forward-references.

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

enum DispatcherBridge {
    /// T6 will implement this. For now a no-op so Renderer's compile path is unbroken.
    static func installIfNeeded(registry: HandlerRegistry) {
        // Intentionally empty — Task 6 wires this to JSClosure + window.__swiflowDispatch.
        _ = registry
    }
}

#endif
