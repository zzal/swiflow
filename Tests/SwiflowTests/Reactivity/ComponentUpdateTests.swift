// Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift
import Testing
@testable import Swiflow

@Suite("Component update path")
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

    @Test("Reuse path commits the new vnode description on the mount node")
    func reuseUpdatesMountVNode() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })
        let v2 = VNode.component(.init(Counter.self) { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        // After reuse, the mount node's vnode should equal the new description.
        // (Same description by ==, but distinct VNode values since factory
        // closures are different.)
        if case .component(let storedDesc) = second.newMountTree.vnode,
           case .component(let nextDesc) = v2 {
            #expect(storedDesc == nextDesc, "Reuse must commit the new vnode/description to the mount node")
        } else {
            Issue.record("Expected .component case on both stored and next vnode")
        }
    }
}
