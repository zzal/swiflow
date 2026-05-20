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
}
