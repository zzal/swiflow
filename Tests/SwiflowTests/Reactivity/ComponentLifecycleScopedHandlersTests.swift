// Tests/SwiflowTests/Reactivity/ComponentLifecycleScopedHandlersTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HandlerRegistry per-Component scope")
struct ComponentLifecycleScopedHandlersTests {
    @Test("openScope/closeScope evicts handlers registered inside scope")
    func scopedHandlersAreEvictedOnClose() {
        let r = HandlerRegistry()
        let h1 = r.register { _ in }                            // outside scope
        r.openScope()
        let h2 = r.register { _ in }                            // inside scope
        let h3 = r.register { _ in }                            // inside scope
        r.closeScope()

        #expect(r.handler(forID: h1.id) != nil)                 // survives
        #expect(r.handler(forID: h2.id) == nil)                 // evicted
        #expect(r.handler(forID: h3.id) == nil)                 // evicted
    }

    @Test("Nested scopes evict independently")
    func nestedScopes() {
        let r = HandlerRegistry()
        r.openScope()
        let outer = r.register { _ in }
        r.openScope()
        let inner = r.register { _ in }
        r.closeScope()
        #expect(r.handler(forID: outer.id) != nil)
        #expect(r.handler(forID: inner.id) == nil)
        r.closeScope()
        #expect(r.handler(forID: outer.id) == nil)
    }

    @Test("activeScopeIndex pins registration to a specific frame, not the top")
    func activeScopeIndexRedirectsRegistration() {
        let r = HandlerRegistry()
        r.openScope(name: "Counter")                             // depth 0
        let parentScopeIdx = r.currentScopeIndex
        let h1 = r.register { _ in }                            // Counter's frame

        r.openScope(name: "Toast")                              // depth 1
        let h2 = r.register { _ in }                            // Toast's frame

        // Simulate Counter re-render: pin to Counter's scope before body
        r.activeScopeIndex = parentScopeIdx
        let h3 = r.register { _ in }                            // must go to Counter's frame
        r.activeScopeIndex = nil

        // Destroy Toast: its scope frame is closed
        r.closeScope()

        #expect(r.handler(forID: h1.id) != nil)                 // original Counter handler
        #expect(r.handler(forID: h2.id) == nil)                 // Toast handler evicted
        #expect(r.handler(forID: h3.id) != nil,
                "Handler registered with activeScopeIndex set must survive child scope closure")
    }

    // Regression: parent component handlers were silently evicted when a child
    // component with exitAnimation was removed in the same diff pass.
    //
    // Root cause: during update(), body was called with the child's scope frame
    // on top of the stack, so new parent handlers landed in the child's frame
    // and were evicted when destroy() closed it.
    @Test("Parent handlers survive after child component with exitAnimation is removed")
    func parentHandlersSurviveChildExitAnimation() {
        // A child component with exitAnimation that registers a handler.
        final class Child: Component {
            static var exitAnimation: String? = "out 0.2s"
            static var exitDuration: Double?  = 0.2
            var body: VNode { div {} }
        }

        // A parent that registers a handler via the shared registry on every
        // body call (simulating what _registerAmbientHandler does in production).
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

        // Initial mount — Parent + Child both present.
        let r1 = diff(mounted: nil,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        let firstClickID = r1.patches.compactMap { p -> Int? in
            if case .addHandler(_, "click", let id) = p { return id }
            return nil
        }.first
        #expect(firstClickID != nil)
        #expect(registry.handler(forID: firstClickID!) != nil)

        // Re-render with showChild = false — triggers animateExit + destroy(Child).
        parent.showChild = false
        let r2 = diff(mounted: r1.newMountTree,
                      next: .component(.init(Parent.self) { parent }),
                      handles: handles, handlers: registry)

        // Child's exit animation must be emitted.
        #expect(r2.patches.contains { if case .animateExit = $0 { return true }; return false })

        // Parent's new click handler (registered during re-render) must survive.
        let newClickID = r2.newMountTree.componentBody?.handlerIds["click"]
        #expect(newClickID != nil)
        #expect(registry.handler(forID: newClickID!) != nil,
                "Parent click handler must not be evicted by child scope closure")
    }
}
