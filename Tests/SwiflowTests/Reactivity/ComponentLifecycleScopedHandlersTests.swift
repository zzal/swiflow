// Tests/SwiflowTests/Reactivity/ComponentLifecycleScopedHandlersTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HandlerRegistry per-Component scope")
struct ComponentLifecycleScopedHandlersTests {

    @Test("openScope/closeScope(_:) evicts handlers registered inside scope")
    func scopedHandlersAreEvictedOnClose() {
        let r = HandlerRegistry()
        let h1 = r.register { _ in }                            // outside any scope — permanent
        let id = r.openScope()
        let h2 = r.withScope(id) { r.register { _ in } }       // scoped
        let h3 = r.withScope(id) { r.register { _ in } }       // scoped
        r.closeScope(id)

        #expect(r.handler(forID: h1.id) != nil)                 // survives (permanent)
        #expect(r.handler(forID: h2.id) == nil)                 // evicted
        #expect(r.handler(forID: h3.id) == nil)                 // evicted
    }

    @Test("Nested scopes evict independently by ID")
    func nestedScopes() {
        let r = HandlerRegistry()
        let outerID = r.openScope()
        let outer = r.withScope(outerID) { r.register { _ in } }
        let innerID = r.openScope()
        let inner = r.withScope(innerID) { r.register { _ in } }

        r.closeScope(innerID)
        #expect(r.handler(forID: outer.id) != nil)
        #expect(r.handler(forID: inner.id) == nil)

        r.closeScope(outerID)
        #expect(r.handler(forID: outer.id) == nil)
    }

    @Test("closeScope(_:) evicts by ScopeID, not by open-scopes position")
    func closeScopeByIDNotByStackPosition() {
        let r = HandlerRegistry()
        let outerID = r.openScope()
        let hOuter = r.withScope(outerID) { r.register { _ in } }
        let innerID = r.openScope()
        let hInner = r.withScope(innerID) { r.register { _ in } }

        // Close outer while inner is still on top of the open-scopes list.
        // With the old popLast() approach this would evict hInner instead.
        r.closeScope(outerID)

        #expect(r.handler(forID: hOuter.id) == nil, "outer's handler must be evicted")
        #expect(r.handler(forID: hInner.id) != nil, "inner's handler must survive")

        r.closeScope(innerID)
        #expect(r.handler(forID: hInner.id) == nil)
    }

    @Test("withScope(_:_:) pins registration to the specified scope")
    func withScopePinsRegistration() {
        let r = HandlerRegistry()
        let counterID = r.openScope(debugName: "Counter")
        let h1 = r.withScope(counterID) { r.register { _ in } }

        let toastID = r.openScope(debugName: "Toast")
        let h2 = r.withScope(toastID) { r.register { _ in } }

        // withScope pins to Counter's scope — even though Toast's is on top
        let h3 = r.withScope(counterID) { r.register { _ in } }

        r.closeScope(toastID)

        #expect(r.handler(forID: h1.id) != nil)                 // original Counter handler
        #expect(r.handler(forID: h2.id) == nil)                 // Toast handler evicted
        #expect(r.handler(forID: h3.id) != nil,
                "Handler registered via withScope must survive child scope closure")

        r.closeScope(counterID)
        #expect(r.handler(forID: h3.id) == nil)                 // evicted on Counter unmount
    }

    @Test("remove(id:) prunes handler from its scope immediately")
    func removeKeepsScopeCompact() {
        let r = HandlerRegistry()
        let id = r.openScope()
        let h1 = r.withScope(id) { r.register { _ in } }
        let h2 = r.withScope(id) { r.register { _ in } }

        // Simulate diffHandlers swapping h1 for a new handler
        r.remove(id: h1.id)

        // h1 must no longer be in the scope; closeScope should not crash
        // and h2 must be correctly evicted
        r.closeScope(id)
        #expect(r.handler(forID: h1.id) == nil)
        #expect(r.handler(forID: h2.id) == nil)
    }

    // MARK: - Integration via diff()

    // Regression: parent component handlers were silently evicted when a child
    // component with exitAnimation was removed in the same diff pass.
    @Test("Parent handlers survive after child component with exitAnimation is removed")
    func parentHandlersSurviveChildExitAnimation() {
        final class Child: Component {
            static var exitAnimation: String? = "out 0.2s"
            static var exitDuration: Double?  = 0.2
            var body: VNode { div {} }
        }

        final class Parent: Component {
            let registry: HandlerRegistry
            var showChild: Bool = true
            init(registry: HandlerRegistry) { self.registry = registry }

            var body: VNode {
                let h = registry.register { _ in }
                let children: [VNode] = showChild
                    ? [.component(.init(Child.self) { Child() })]
                    : []
                return .element(ElementData(tag: "div", handlers: ["click": h], children: children))
            }
        }

        let handles  = HandleAllocator()
        let registry = HandlerRegistry()
        let parent   = Parent(registry: registry)

        let r1 = diff(mounted: nil,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        // First-render click handler must exist
        let firstClickID = r1.patches.compactMap { p -> Int? in
            if case .addHandler(_, "click", let id) = p { return id }
            return nil
        }.first
        #expect(firstClickID != nil)
        #expect(registry.handler(forID: firstClickID!) != nil)

        // Re-render with showChild = false — triggers animateExit + destroy(Child)
        parent.showChild = false
        let r2 = diff(mounted: r1.newMountTree,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        #expect(r2.patches.contains { if case .animateExit = $0 { return true }; return false },
                "Child with exitAnimation must produce animateExit patch")

        let newClickID = r2.newMountTree.componentBody?.handlerIds["click"]
        #expect(newClickID != nil)
        #expect(registry.handler(forID: newClickID!) != nil,
                "Parent click handler must not be evicted by child scope closure")

        // Handler must actually dispatch
        var fired = false
        _ = registry.withScope(r2.newMountTree.scopeID!) {
            registry.register { _ in fired = true }
        }
        registry.dispatch(id: newClickID!, event: EventInfo(type: "click"))
        // The parent's handler is a no-op closure (`{ _ in }`), so dispatch
        // not crashing + handler being found in registry is the correctness proof.
        // The separate "dispatch fires" test below covers the firing path.
        #expect(registry.handler(forID: newClickID!) != nil)
    }

    // Regression: keyed sibling B's handlers were evicted when sibling A
    // was destroyed because the old popLast() approach closed B's scope.
    @Test("Keyed sibling handlers survive after other sibling is removed")
    func keyedSiblingHandlersSurviveAfterOtherSiblingRemoved() {
        // A Leaf component that registers a click handler and invokes a callback.
        final class Leaf: Component {
            let registry: HandlerRegistry
            var onFire: () -> Void
            init(registry: HandlerRegistry, onFire: @escaping () -> Void = {}) {
                self.registry = registry; self.onFire = onFire
            }
            var body: VNode {
                let h = registry.register { [self] _ in onFire() }
                return .element(ElementData(tag: "div", handlers: ["click": h]))
            }
        }

        final class Holder: Component {
            let registry: HandlerRegistry
            var showA: Bool = true
            init(registry: HandlerRegistry) { self.registry = registry }

            var body: VNode {
                var kids: [VNode] = []
                if showA {
                    kids.append(.component(.init(Leaf.self, key: "A") {
                        Leaf(registry: self.registry)
                    }))
                }
                kids.append(.component(.init(Leaf.self, key: "B") {
                    Leaf(registry: self.registry)
                }))
                return .element(ElementData(tag: "div", children: kids))
            }
        }

        let handles  = HandleAllocator()
        let registry = HandlerRegistry()
        let holder   = Holder(registry: registry)

        let r1 = diff(mounted: nil,
                      next: .component(.init(Holder.self) { holder }),
                      handles: handles, handlers: registry)

        // Locate B's body node after initial mount (A is child[0], B is child[1])
        let holderBody = r1.newMountTree.componentBody!  // div
        let bAnchorMount = holderBody.children[1]        // B's anchor
        let bBodyMount   = bAnchorMount.componentBody!   // B's div
        let bClickIDMount = bBodyMount.handlerIds["click"]
        #expect(bClickIDMount != nil)
        #expect(registry.handler(forID: bClickIDMount!) != nil,
                "B's handler must exist after initial mount")

        // Remove A — keyed diff updates B BEFORE destroying A (step 6 then 7)
        holder.showA = false
        let r2 = diff(mounted: r1.newMountTree,
                      next: .component(.init(Holder.self) { holder }),
                      handles: handles, handlers: registry)

        // B's new handler (registered during re-render) must survive
        let holderBody2 = r2.newMountTree.componentBody!
        let bAnchorUpdate = holderBody2.children[0]      // only B remains
        let bBodyUpdate   = bAnchorUpdate.componentBody!
        let bClickIDUpdate = bBodyUpdate.handlerIds["click"]
        #expect(bClickIDUpdate != nil)
        #expect(registry.handler(forID: bClickIDUpdate!) != nil,
                "B's click handler must survive after keyed sibling A is destroyed")
    }

    @Test("Dispatching a registered handler fires the closure")
    func dispatchFiresClosure() {
        let r = HandlerRegistry()
        var received: String?
        let id = r.openScope()
        let h = r.withScope(id) { r.register { event in received = event.type } }
        r.closeScope(id)

        // Handler is evicted after closeScope — re-register outside any scope for dispatch test
        let h2 = r.register { event in received = event.type }
        r.dispatch(id: h2.id, event: EventInfo(type: "click"))
        #expect(received == "click")
        _ = h  // suppress unused warning
    }

    @Test("Parent handler dispatches after child exitAnimation removal")
    func parentHandlerDispatchesAfterChildRemoval() {
        final class Child: Component {
            static var exitAnimation: String? = "out 0.1s"
            static var exitDuration: Double?  = 0.1
            var body: VNode { div {} }
        }

        final class Parent: Component {
            let registry: HandlerRegistry
            var showChild: Bool = true
            var fireCount: Int = 0
            init(registry: HandlerRegistry) { self.registry = registry }

            var body: VNode {
                let h = registry.register { [self] _ in fireCount += 1 }
                let children: [VNode] = showChild
                    ? [.component(.init(Child.self) { Child() })]
                    : []
                return .element(ElementData(tag: "div", handlers: ["click": h], children: children))
            }
        }

        let handles  = HandleAllocator()
        let registry = HandlerRegistry()
        let parent   = Parent(registry: registry)

        let r1 = diff(mounted: nil,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        parent.showChild = false
        let r2 = diff(mounted: r1.newMountTree,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        let clickID = r2.newMountTree.componentBody!.handlerIds["click"]!
        registry.dispatch(id: clickID, event: EventInfo(type: "click"))
        #expect(parent.fireCount == 1,
                "Parent click handler must fire after child with exitAnimation is removed")
    }
}
