// Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
import Testing
@testable import Swiflow

@Suite("Scoped re-render")
@MainActor
struct ScopedRerenderTests {

    // A child component nested inside a parent's body, so the mount tree has
    // a real anchor → body → anchor chain to walk.
    final class Child: Component {
        var label: String = "child"
        var body: VNode { p(label) }
    }
    final class Parent: Component {
        let child = Child()
        var body: VNode {
            div { VNode.component(.init(Child.self) { self.child }) }
        }
    }

    private func mountParent() -> (root: MountNode, parent: Parent, child: Child) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let parent = Parent()
        let v = VNode.component(.init(Parent.self) { parent })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        return (result.newMountTree, parent, parent.child)
    }

    @Test("finds the nested child anchor by instance identity")
    func findsNestedAnchor() {
        let (root, _, child) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))
        #expect(anchor != nil)
        #expect(anchor?.component?.instance === child)
    }

    @Test("returns the root when the root instance matches")
    func findsRoot() {
        let (root, parent, _) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(parent))
        #expect(anchor === root)
    }

    @Test("returns nil for an instance not in the tree")
    func findsNothing() {
        let (root, _, _) = mountParent()
        let stray = Child()
        #expect(findComponentAnchor(in: root, matching: ObjectIdentifier(stray)) == nil)
    }

    @Test("detects an environmentOverride ancestor")
    func detectsEnvOverrideAncestor() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = Child()
        // Wrap the child anchor in an environmentOverride node.
        let v = VNode.environmentOverride(
            EnvironmentValues(),
            .component(.init(Child.self) { child })
        )
        let root = diff(mounted: nil, next: v, handles: handles, handlers: handlers).newMountTree
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))
        #expect(anchor != nil)
        #expect(hasEnvironmentOverrideAncestor(anchor!) == true)
    }

    @Test("no false positive without an override ancestor")
    func noEnvOverrideAncestor() {
        let (root, _, child) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))!
        #expect(hasEnvironmentOverrideAncestor(anchor) == false)
    }

    @Test("single dirty nested component → scoped at its anchor")
    func planScopesSingleDirty() {
        let (root, _, child) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child)])
        guard case .scoped(let anchor) = plan else { Issue.record("expected .scoped"); return }
        #expect(anchor.component?.instance === child)
    }

    @Test("more than one dirty component → full")
    func planFullOnMultiDirty() {
        let (root, parent, child) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child), ObjectIdentifier(parent)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("root dirty → full (full render is already minimal for the root)")
    func planFullOnRootDirty() {
        let (root, parent, _) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(parent)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("dirty instance absent from tree → full")
    func planFullOnMissing() {
        let (root, _, _) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(Child())])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("dirty anchor under environmentOverride → full")
    func planFullOnEnvOverride() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = Child()
        let v = VNode.environmentOverride(
            EnvironmentValues(),
            .component(.init(Child.self) { child })
        )
        let root = diff(mounted: nil, next: v, handles: handles, handlers: handlers).newMountTree
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }
}
