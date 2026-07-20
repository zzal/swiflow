// Sources/Swiflow/Diff/Teardown.swift

/// The one teardown routine shared by every render root.
///
/// `destroy` gates its `componentDidUnmount` notification on
/// `RenderObserverBox.current`. Before this helper existed the two roots had
/// drifted: `TestRenderer.unmount()` installed the query client as the
/// observer while the browser `Renderer.teardown()` installed nothing — so
/// query-subscription cleanup fired on unmount in tests but NEVER in the
/// browser (the harness green-lit a callback production didn't deliver, and
/// a browser-side subscription leak was unobservable). Both roots now call
/// this; the divergence is dead by construction.
///
/// Installs `observer` for exactly the duration of the destroy walk and
/// restores the ambient to nil after — teardown is terminal, there is no
/// prior render context to restore. Returns the removal patches; the browser
/// root ships them to the driver, the headless root discards them.
@MainActor
package func teardownMountTree(
    _ tree: MountNode,
    handlers: HandlerRegistry,
    observer: (any RenderObserver)?
) -> [Patch] {
    RenderObserverBox.current = observer
    defer { RenderObserverBox.current = nil }
    var patches: [Patch] = []
    destroy(tree, into: &patches, handlers: handlers)
    return patches
}
