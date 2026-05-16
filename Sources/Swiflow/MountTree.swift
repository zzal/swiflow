// Sources/Swiflow/MountTree.swift

/// A persistent counterpart to a committed `VNode` tree. The diff engine
/// reads the `MountNode` (left-hand side) against a freshly produced `VNode`
/// (right-hand side) and emits `Patch`es; the mount tree is updated in place
/// after each diff so subsequent renders compare against the new state.
///
/// `MountNode` is a class (reference type) because the parent/child graph is
/// mutated in place. The parent pointer is `weak` to avoid retain cycles.
public final class MountNode {
    /// The integer handle assigned at mount time, stable for this node's
    /// lifetime. Matches the handle the JS driver knows it by.
    public let handle: Int
    /// The currently-committed virtual node for this position. Mutated in
    /// place by the diff engine after each successful update.
    public var vnode: VNode
    /// Live mount-tree children, in document order.
    public private(set) var children: [MountNode]

    /// Maps event name (e.g. `"click"`) to the handler ID currently registered
    /// in `HandlerRegistry`. Mirrored on the JS driver side via
    /// `Patch.addHandler` / `.removeHandler`.
    public var handlerIds: [String: Int]

    /// Weak back-pointer to the parent `MountNode`. `nil` for the root or
    /// for detached subtrees.
    public private(set) weak var parent: MountNode?

    /// Creates a `MountNode`. Wires `parent` pointers for any pre-supplied
    /// children so callers don't need a separate pass.
    public init(
        handle: Int,
        vnode: VNode,
        children: [MountNode] = [],
        handlerIds: [String: Int] = [:]
    ) {
        self.handle = handle
        self.vnode = vnode
        self.children = children
        self.handlerIds = handlerIds
        for child in children {
            child.parent = self
        }
    }

    /// Appends a child and updates its parent pointer.
    public func addChild(_ child: MountNode) {
        children.append(child)
        child.parent = self
    }

    /// Inserts a child at `index` and updates its parent pointer.
    public func insertChild(_ child: MountNode, at index: Int) {
        children.insert(child, at: index)
        child.parent = self
    }

    /// Removes the child at `index` and clears its parent pointer.
    /// Caller is responsible for emitting any `destroyNode` / `removeChild`
    /// patches.
    public func removeChild(at index: Int) {
        let child = children.remove(at: index)
        child.parent = nil
    }

    /// Replaces the child at `index` with a fresh `MountNode`, clearing the
    /// old child's parent pointer and wiring the new one. Caller is
    /// responsible for any DOM-side `insertBefore` / `appendChild` /
    /// `destroyNode` patches; this only updates the in-memory mount tree.
    public func replaceChild(at index: Int, with child: MountNode) {
        children[index].parent = nil
        children[index] = child
        child.parent = self
    }
}
