// Sources/Swiflow/Diff/ScopedRerender.swift
//
// Scoped re-render (issue #89). A single-component @State change should
// re-render only that component's subtree, not the whole tree from the root.
// All decision + execution logic lives here so it is host-testable; the
// WASM-only Renderer/RAFScheduler hold only thin wiring.

/// Walks `node`'s subtree (componentBody + children) and returns the
/// component-anchor `MountNode` whose live instance has identity `id`, or
/// `nil` if no such anchor exists. Pure: it reads the committed tree and
/// holds no state, so it can never go stale.
@MainActor
package func findComponentAnchor(in node: MountNode, matching id: ObjectIdentifier) -> MountNode? {
    if let c = node.component, ObjectIdentifier(c.instance) == id { return node }
    if let body = node.componentBody,
       let found = findComponentAnchor(in: body, matching: id) {
        return found
    }
    for child in node.children {
        if let found = findComponentAnchor(in: child, matching: id) { return found }
    }
    return nil
}
