// Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HandlerRegistry: named scopes")
struct HandlerRegistryNamedScopeTests {

    @Test("openScope(name:) with two named scopes reports per-scope counts")
    func namedScopesCounts() {
        let r = HandlerRegistry()
        let id0 = r.openScope(name: "0")
        r.register { _ in }
        r.register { _ in }
        let id1 = r.openScope(name: "1")
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["0"] == 2)
        #expect(counts["1"] == 1)
        r.closeScope(id: id0)
        r.closeScope(id: id1)
    }

    @Test("closeScope(id:) removes its name from countPerScope()")
    func closeScopeRemovesName() {
        let r = HandlerRegistry()
        let idA = r.openScope(name: "A")
        r.register { _ in }
        r.closeScope(id: idA)
        #expect(r.countPerScope()["A"] == nil)
        #expect(r.countPerScope().isEmpty)
    }

    @Test("openScope() with default name uses empty string key")
    func defaultNameIsEmptyString() {
        let r = HandlerRegistry()
        let id = r.openScope()
        r.register { _ in }
        #expect(r.countPerScope()[""] == 1)
        r.closeScope(id: id)
    }

    @Test("countPerScope is empty when no scopes are open")
    func emptyWhenNoScopes() {
        let r = HandlerRegistry()
        r.register { _ in }    // registration outside any scope
        #expect(r.countPerScope().isEmpty)
    }

    @Test("duplicate scope names accumulate counts")
    func duplicateNamesAccumulate() {
        let r = HandlerRegistry()
        let id1 = r.openScope(name: "x")
        r.register { _ in }
        let id2 = r.openScope(name: "x")
        r.register { _ in }
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["x"] == 3)
        r.closeScope(id: id1)
        r.closeScope(id: id2)
    }

    @Test("open, close, open again: second scope is correctly tracked")
    func reopenAfterClose() {
        let r = HandlerRegistry()
        let idA = r.openScope(name: "A")
        r.register { _ in }
        r.closeScope(id: idA)
        let idB = r.openScope(name: "B")
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["A"] == nil)
        #expect(counts["B"] == 1)
        r.closeScope(id: idB)
    }

    @Test("closeScope(id:) targets its own frame, not the stack top")
    func closeScopeByIDNotByPosition() {
        let r = HandlerRegistry()
        let idA = r.openScope(name: "A")
        let hA = r.register { _ in }
        let idB = r.openScope(name: "B")
        let hB = r.register { _ in }

        // Close A while B is still on top — with popLast() this would
        // evict B's handler instead of A's.
        r.closeScope(id: idA)

        #expect(r.handler(forID: hA.id) == nil, "A's handler must be evicted")
        #expect(r.handler(forID: hB.id) != nil, "B's handler must survive")
        r.closeScope(id: idB)
    }
}
