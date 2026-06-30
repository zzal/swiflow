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
}
