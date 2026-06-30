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

    // A root component whose body is JUST another component (no element wrapper),
    // so the inner anchor has no DOM-tracked ancestor between it and the root.
    final class ShellInner: Component {
        var flip = false
        var body: VNode { flip ? p("b") : div { p("a") } }   // root-element type can swap
    }
    final class ShellRoot: Component {
        let inner = ShellInner()
        var body: VNode { VNode.component(.init(ShellInner.self) { self.inner }) }
    }

    @Test("dirty anchor with no DOM-tracked ancestor → full (root→component shell, body could tag-swap)")
    func planFullWhenNoDomAncestor() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let shell = ShellRoot()
        let root = diff(mounted: nil, next: .component(.init(ShellRoot.self) { shell }),
                        handles: handles, handlers: handlers).newMountTree
        // The inner anchor's only ancestor is the ShellRoot anchor (structural),
        // whose parent is nil → no DOM ancestor → must fall back to full so the
        // renderer's replaceMount covers a potential body root-element swap.
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(shell.inner)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    // Lifecycle-recording components. `events` is shared so a test can assert
    // exactly which instances' onChange/onAppear fired during a scoped pass.
    final class RecChild: Component {
        let name: String
        let events: EventLog
        var label = "a"
        init(name: String, events: EventLog) { self.name = name; self.events = events }
        var body: VNode { p(label) }
        func onChange() { events.log.append("change:\(name)") }
        func onAppear() { events.log.append("appear:\(name)") }
    }
    final class EventLog { var log: [String] = [] }

    final class RecParent: Component {
        let events: EventLog
        let child: RecChild
        init(events: EventLog) { self.events = events; self.child = RecChild(name: "child", events: events) }
        var body: VNode {
            div {
                p("parent-chrome")
                VNode.component(.init(RecChild.self) { self.child })
            }
        }
        func onChange() { events.log.append("change:parent") }
    }

    @Test("scopedRerender re-renders only the child subtree and fires only its lifecycle")
    func scopedReRendersChildOnly() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let events = EventLog()
        let parent = RecParent(events: events)
        let root = diff(mounted: nil, next: .component(.init(RecParent.self) { parent }),
                        handles: handles, handlers: handlers).newMountTree
        events.log.removeAll()  // discard first-mount onAppear noise

        // Mutate ONLY the child's body, then scoped-rerender at the child anchor.
        parent.child.label = "b"
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(parent.child))!
        let result = scopedRerender(anchor: anchor, handles: handles, handlers: handlers, scheduler: nil)
        // Caller fires the lifecycle (scopedRerender no longer does — the
        // renderer fires it AFTER shipping patches).
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: result.preExistingIDs)

        // (a) patches updated the child's text and nothing else.
        let setTexts: [String] = result.patches.compactMap {
            if case .setText(_, let t) = $0 { return t } else { return nil }
        }
        #expect(setTexts == ["b"])

        // (b) the reused instance is identical and the anchor object is unchanged.
        #expect(anchor.component?.instance === parent.child)

        // (c) only the child's onChange fired; the parent's did NOT.
        #expect(events.log == ["change:child"])
    }

    @Test("a component mounted DURING the scoped pass fires onAppear, not onChange")
    func scopedFiresAppearForFreshChild() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let events = EventLog()

        // Parent whose child conditionally renders a grandchild.
        final class GrandHolder: Component {
            let events: EventLog
            var showGrand = false
            let grand: RecChild
            init(events: EventLog) { self.events = events; self.grand = RecChild(name: "grand", events: events) }
            var body: VNode {
                if showGrand {
                    return div { VNode.component(.init(RecChild.self) { self.grand }) }
                } else {
                    return div { p("empty") }
                }
            }
            func onChange() { events.log.append("change:holder") }
        }
        let holder = GrandHolder(events: events)
        let root = diff(mounted: nil, next: .component(.init(GrandHolder.self) { holder }),
                        handles: handles, handlers: handlers).newMountTree
        events.log.removeAll()

        holder.showGrand = true
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(holder))!
        let result = scopedRerender(anchor: anchor, handles: handles, handlers: handlers, scheduler: nil)
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: result.preExistingIDs)

        // holder survived → onChange; grand is freshly mounted → onAppear.
        #expect(events.log.contains("change:holder"))
        #expect(events.log.contains("appear:grand"))
        #expect(!events.log.contains("change:grand"))
    }
}
