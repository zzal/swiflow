// Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift
import Testing
@testable import Swiflow

@Suite("HandlerRegistry: named scopes")
struct HandlerRegistryNamedScopeTests {

    @Test("openScope(name:) with two named scopes reports per-scope counts")
    func namedScopesCounts() {
        let r = HandlerRegistry()
        r.openScope(name: "0")
        r.register { _ in }
        r.register { _ in }
        r.openScope(name: "1")
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["0"] == 2)
        #expect(counts["1"] == 1)
        #expect(counts.values.reduce(0, +) == 3)
    }

    @Test("closeScope removes its name from countPerScope()")
    func closeScopeRemovesName() {
        let r = HandlerRegistry()
        r.openScope(name: "A")
        r.register { _ in }
        r.closeScope()
        #expect(r.countPerScope()["A"] == nil)
        #expect(r.countPerScope().isEmpty)
    }

    @Test("openScope() with default name uses empty string key")
    func defaultNameIsEmptyString() {
        let r = HandlerRegistry()
        r.openScope()   // no name argument
        r.register { _ in }
        #expect(r.countPerScope()[""] == 1)
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
        r.openScope(name: "x")
        r.register { _ in }
        r.openScope(name: "x")
        r.register { _ in }
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["x"] == 3)
    }
}
