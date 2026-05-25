// Sources/Swiflow/MountTree.swift

/// A persistent counterpart to a committed `VNode` tree. The diff engine
/// reads the `MountNode` (left-hand side) against a freshly produced `VNode`
/// (right-hand side) and emits `Patch`es; the mount tree is updated in place
/// after each diff so subsequent renders compare against the new state.
///
/// `MountNode` is a class (reference type) because the parent/child graph is
/// mutated in place. The parent pointer is `weak` to avoid retain cycles.
package final class MountNode {
    /// The integer handle assigned at mount time, stable for this node's
    /// lifetime. Matches the handle the JS driver knows it by.
    package let handle: Int
    /// The currently-committed virtual node for this position. Mutated in
    /// place by the diff engine after each successful update.
    package var vnode: VNode
    /// Live mount-tree children, in document order.
    package private(set) var children: [MountNode]

    /// Maps event name (e.g. `"click"`) to the handler ID currently registered
    /// in `HandlerRegistry`. Mirrored on the JS driver side via
    /// `Patch.addHandler` / `.removeHandler`.
    package var handlerIds: [String: Int]

    /// For a component-anchor mount node, the live instance. `nil` for
    /// every other node kind (text, rawHTML, element). Populated only
    /// for component-anchor nodes; see `VNode.component`.
    ///
    /// `var` (not `let`) so Task 5's update path can swap the slot
    /// when an instance is replaced. Currently set exactly once at
    /// mount time; future tasks may mutate.
    package var component: AnyComponent?

    /// Stable scope ID returned by `HandlerRegistry.openScope(debugName:)` when
    /// this component-anchor node was mounted. Passed to `closeScope(_:)` at
    /// unmount and to `withScope(_:_:)` before each body re-evaluation so
    /// handler ownership is always correct regardless of sibling scope ordering.
    /// `nil` for non-component nodes.
    package var scopeID: ScopeID?

    /// For a component-anchor mount node, the mount-tree root of the
    /// instance's `body`. `nil` for every other node kind. Populated only
    /// for component-anchor nodes; see `VNode.component`.
    ///
    /// `var` (not `let`) so Task 5's update path can replace the body
    /// subtree when an existing instance re-renders. Currently set
    /// exactly once at mount time.
    package var componentBody: MountNode?

    /// The DOM-facing handle for this node — the one the JS driver knows.
    ///
    /// For ordinary nodes (text, rawHTML, element) it's `handle` itself.
    /// For a component anchor it's the body's `domHandle` (walking through
    /// nested anchors when a component's body is itself a `.component`).
    ///
    /// Use this whenever building a patch that references the DOM-side node
    /// (`appendChild`, `insertBefore`, `removeChild`). The plain `handle`
    /// is structural identity used by the diff; the DOM never sees it.
    package var domHandle: Int {
        componentBody?.domHandle ?? handle
    }

    /// Weak back-pointer to the parent `MountNode`. `nil` for the root or
    /// for detached subtrees.
    package private(set) weak var parent: MountNode?

    /// Creates a `MountNode`. Wires `parent` pointers for any pre-supplied
    /// children so callers don't need a separate pass.
    package init(
        handle: Int,
        vnode: VNode,
        children: [MountNode] = [],
        handlerIds: [String: Int] = [:],
        component: AnyComponent? = nil,
        componentBody: MountNode? = nil,
        scopeID: ScopeID? = nil
    ) {
        self.handle = handle
        self.vnode = vnode
        self.children = children
        self.handlerIds = handlerIds
        self.component = component
        self.componentBody = componentBody
        self.scopeID = scopeID
        for child in children {
            child.parent = self
        }
    }

    /// Appends a child and updates its parent pointer.
    package func addChild(_ child: MountNode) {
        children.append(child)
        child.parent = self
    }

    /// Inserts a child at `index` and updates its parent pointer.
    package func insertChild(_ child: MountNode, at index: Int) {
        children.insert(child, at: index)
        child.parent = self
    }

    /// Removes the child at `index` and clears its parent pointer.
    /// Caller is responsible for emitting any `destroyNode` / `removeChild`
    /// patches.
    package func removeChild(at index: Int) {
        let child = children.remove(at: index)
        child.parent = nil
    }

    /// Replaces the child at `index` with a fresh `MountNode`, clearing the
    /// old child's parent pointer and wiring the new one. Caller is
    /// responsible for any DOM-side `insertBefore` / `appendChild` /
    /// `destroyNode` patches; this only updates the in-memory mount tree.
    package func replaceChild(at index: Int, with child: MountNode) {
        children[index].parent = nil
        children[index] = child
        child.parent = self
    }
}
