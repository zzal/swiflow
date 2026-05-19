// Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift
import Testing
@testable import Swiflow

@Suite("Component update path")
@MainActor
struct ComponentUpdateTests {

    final class Counter: Component {
        var n: Int = 0
        var body: VNode { p("count=\(n)") }
    }

    final class Greeter: Component {
        var body: VNode { p("hi") }
    }

    @Test("Same description at same position reuses the instance; body is re-rendered")
    func reuseOnTypeAndKeyMatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let originalInstance = first.newMountTree.component?.instance as? Counter
        #expect(originalInstance != nil)
        originalInstance?.n = 42

        // Build a new VNode tree with the same description. Mutate the
        // instance's state to verify the diff re-renders the body (rather
        // than producing the "0" body from a fresh factory).
        let v2 = VNode.component(.init(Counter.self) { Counter() })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        // Reused instance? Same reference.
        #expect(second.newMountTree.component?.instance === originalInstance)

        // The body's text node should have been updated to "count=42"
        // via a setText patch.
        let setTextTo42 = second.patches.contains {
            if case .setText(_, let text) = $0, text == "count=42" { return true }
            return false
        }
        #expect(setTextTo42, "Expected setText patch to 'count=42', got patches: \(second.patches)")
    }

    @Test("Different component type at same position destroys old and mounts new")
    func replaceOnTypeMismatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })
        let v2 = VNode.component(.init(Greeter.self) { Greeter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let oldDOMHandle = first.newMountTree.domHandle

        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        let destroyed = second.patches.contains {
            if case .destroyNode(let h) = $0, h == oldDOMHandle { return true }
            return false
        }
        #expect(destroyed, "Expected destroyNode for the old component's body DOM handle")

        // New mount should have a different instance reference.
        let oldInstance = first.newMountTree.component?.instance
        let newInstance = second.newMountTree.component?.instance
        #expect(newInstance !== oldInstance)
    }

    @Test("Different key at same position destroys old and mounts new")
    func replaceOnKeyMismatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self, key: "a") { Counter() })
        let v2 = VNode.component(.init(Counter.self, key: "b") { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let oldDOMHandle = first.newMountTree.domHandle
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        let destroyed = second.patches.contains {
            if case .destroyNode(let h) = $0, h == oldDOMHandle { return true }
            return false
        }
        #expect(destroyed)
    }

    @Test("Reuse path commits a .component vnode on the mount node (limited probe)")
    func reuseUpdatesMountVNode() {
        // KNOWN LIMITATION: ComponentDescription.== compares only typeID +
        // key, so v1's and v2's descriptions are == regardless of which one
        // is stored. This test cannot falsify the production line
        // `mounted.vnode = next` (Diff.swift's reuse arm) — it would pass
        // even if that assignment were removed. We assert the weaker
        // property that SOME .component vnode is stored, primarily to
        // catch a regression where the slot is left as the old element
        // case or set to .text/.rawHTML. Strengthening this to a true
        // identity probe needs a production-API change (e.g. a `testTag`
        // field on ComponentDescription), deferred until justified.
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })
        let v2 = VNode.component(.init(Counter.self) { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        if case .component(let storedDesc) = second.newMountTree.vnode,
           case .component(let nextDesc) = v2 {
            #expect(storedDesc == nextDesc, "Mount node's stored vnode should be a .component with the same typeID + key as the next render")
        } else {
            Issue.record("Expected .component case on both stored and next vnode")
        }
    }

    @Test("Reuse path correctly rewires componentBody when body root kind changes across renders")
    func reuseBodyKindChange() {
        // The recursive update() in the reuse arm returns a fresh MountNode
        // ONLY when the body's root case kind changes (forcing destroy +
        // mount of the body subtree). This test forces that branch by
        // having Chameleon switch its body from .element to .text between
        // renders. Without `mounted.componentBody = newBodyMount` in the
        // reuse arm, the stale element body would remain in the slot.
        final class Chameleon: Component {
            var showText = false
            var body: VNode { showText ? .text("hi") : p("hello") }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Chameleon.self) { Chameleon() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let instance = first.newMountTree.component?.instance as? Chameleon
        #expect(instance != nil)
        instance?.showText = true  // next body() will now return .text, not .element

        let v2 = VNode.component(.init(Chameleon.self) { Chameleon() })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        // componentBody slot must now be a .text MountNode — proves the
        // reuse arm wrote the recursive update()'s freshly-returned
        // MountNode into the slot.
        if case .text(let t) = second.newMountTree.componentBody?.vnode {
            #expect(t == "hi")
        } else {
            Issue.record("componentBody should be a .text MountNode after kind change, got \(String(describing: second.newMountTree.componentBody?.vnode))")
        }

        // The old .element body must have produced a destroyNode patch.
        let hasDestroyNode = second.patches.contains {
            if case .destroyNode = $0 { return true }
            return false
        }
        #expect(hasDestroyNode, "Old element body must be destroyed when body kind changes")

        // And the new .text body must have produced a createText patch.
        let createsText = second.patches.contains {
            if case .createText(_, let text) = $0, text == "hi" { return true }
            return false
        }
        #expect(createsText, "New .text body must be created with 'hi'")
    }
}
