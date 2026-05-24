// Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HandlerRegistry: named scopes")
struct HandlerRegistryNamedScopeTests {

    @Test("openScope(debugName:) with two named scopes reports per-scope counts")
    func namedScopesCounts() {
        let r = HandlerRegistry()
        let id0 = r.openScope(debugName: "0")
        r.withScope(id0) { r.register { _ in } }
        r.withScope(id0) { r.register { _ in } }
        let id1 = r.openScope(debugName: "1")
        r.withScope(id1) { r.register { _ in } }
        let counts = r.countPerScope()
        #expect(counts["0"] == 2)
        #expect(counts["1"] == 1)
        r.closeScope(id0)
        r.closeScope(id1)
    }

    @Test("closeScope(_:) removes its name from countPerScope()")
    func closeScopeRemovesName() {
        let r = HandlerRegistry()
        let idA = r.openScope(debugName: "A")
        r.withScope(idA) { r.register { _ in } }
        r.closeScope(idA)
        #expect(r.countPerScope()["A"] == nil)
        #expect(r.countPerScope().isEmpty)
    }

    @Test("openScope() with default debugName uses empty string key")
    func defaultNameIsEmptyString() {
        let r = HandlerRegistry()
        let id = r.openScope()
        r.withScope(id) { r.register { _ in } }
        #expect(r.countPerScope()[""] == 1)
        r.closeScope(id)
    }

    @Test("countPerScope is empty when no scopes are open")
    func emptyWhenNoScopes() {
        let r = HandlerRegistry()
        r.register { _ in }    // intentionally permanent — no scope open
        #expect(r.countPerScope().isEmpty)
    }

    @Test("duplicate scope debugNames accumulate counts")
    func duplicateNamesAccumulate() {
        let r = HandlerRegistry()
        let id1 = r.openScope(debugName: "x")
        r.withScope(id1) { r.register { _ in } }
        let id2 = r.openScope(debugName: "x")
        r.withScope(id2) { r.register { _ in } }
        r.withScope(id2) { r.register { _ in } }
        let counts = r.countPerScope()
        #expect(counts["x"] == 3)
        r.closeScope(id1)
        r.closeScope(id2)
    }

    @Test("open, close, open again: second scope is correctly tracked")
    func reopenAfterClose() {
        let r = HandlerRegistry()
        let idA = r.openScope(debugName: "A")
        r.withScope(idA) { r.register { _ in } }
        r.closeScope(idA)
        let idB = r.openScope(debugName: "B")
        r.withScope(idB) { r.register { _ in } }
        let counts = r.countPerScope()
        #expect(counts["A"] == nil)
        #expect(counts["B"] == 1)
        r.closeScope(idB)
    }

    @Test("closeScope(_:) targets its own scope, not the open-scopes top")
    func closeScopeByIDNotByPosition() {
        let r = HandlerRegistry()
        let idA = r.openScope(debugName: "A")
        let hA = r.withScope(idA) { r.register { _ in } }
        let idB = r.openScope(debugName: "B")
        let hB = r.withScope(idB) { r.register { _ in } }

        // Close A while B is still on top.
        r.closeScope(idA)

        #expect(r.handler(forID: hA.id) == nil, "A's handler must be evicted")
        #expect(r.handler(forID: hB.id) != nil, "B's handler must survive")
        r.closeScope(idB)
    }
}

#if DEBUG
@MainActor
@Suite("HandlerRegistry: unscoped-register diagnostic (debug-only)")
struct HandlerRegistryUnscopedRegisterTests {

    @Test("register outside withScope while scopes are open fires swiflowDiagnostic")
    func unscopedRegisterFiresDiagnostic() {
        let r = HandlerRegistry()
        let id = r.openScope(debugName: "TestScope")

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        _ = r.register { _ in }   // triggers diagnostic — no withScope active

        #expect(captured.count == 1,
                "Expected exactly one diagnostic; got: \(captured)")
        #expect(captured.first?.contains("withScope") == true,
                "Diagnostic must name withScope; got: \(captured.first ?? "(none)")")
        #expect(captured.first?.contains("1 scope(s)") == true,
                "Diagnostic must report the open scope count")

        r.closeScope(id)
    }

    @Test("register outside withScope with no scopes open does not fire swiflowDiagnostic")
    func permanentRegisterWithNoScopesIsQuiet() {
        let r = HandlerRegistry()
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        _ = r.register { _ in }   // intentionally permanent — no scopes open

        #expect(captured.isEmpty,
                "Permanent registration with no scopes open must not fire a diagnostic")
    }

    @Test("register inside withScope does not fire swiflowDiagnostic")
    func scopedRegisterIsQuiet() {
        let r = HandlerRegistry()
        let id = r.openScope(debugName: "TestScope")

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        r.withScope(id) { _ = r.register { _ in } }   // correctly scoped

        #expect(captured.isEmpty,
                "Scoped registration must not fire a diagnostic")
        r.closeScope(id)
    }
}
#endif
