// Sources/SwiflowWeb/Renderer.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Owns Swiflow's per-application render state in a WASM/browser environment.
///
/// A single Renderer is created by `Swiflow.render(_:into:)` and looked up by
/// `Swiflow.rerender()` through module-private ambient storage. Multiple
/// roots are out of scope for Phase 2a.
final class Renderer {
    let viewProducer: () -> VNode
    let selector: String
    let handles: HandleAllocator
    let handlers: HandlerRegistry
    var mountTree: MountNode?

    init(viewProducer: @escaping () -> VNode, selector: String) {
        self.viewProducer = viewProducer
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil
    }

    /// Runs the producer, diffs against the current mount tree, encodes
    /// patches into a JSArray, hands the array to `window.swiflow.applyPatches`,
    /// and (on first call) tells the driver to attach the root node at
    /// `selector`.
    func renderOnce() {
        let next = viewProducer()
        let result = diff(
            mounted: mountTree,
            next: next,
            handles: handles,
            handlers: handlers
        )

        // Encode patches to a JSArray.
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in result.patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }

        // Ship the batch across the bridge in one call.
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(result.newMountTree.handle)),
                JSValue.string(selector)
            )
        }
    }
}

#endif
