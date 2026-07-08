// Tests/SwiflowRouterTests/RouterContextParamTests.swift
//
// Audit IV Wave-2 #4: typed path params. A matched route guarantees its
// declared :param captures are present in ctx.params (a full match
// consumes every segment; nested routes merge ancestor params), so
// param(_:) is non-optional and a missing key means a typo'd —
// undeclared — NAME: a programmer error, DEBUG-warned via swiflowWarn.
// Unparseable VALUES for param(_:as:) are user-typed URL input and stay
// a silent nil (the app renders its fallback).
import Testing
import Swiflow
@testable import SwiflowRouter

@Suite("RouterContext typed param accessors")
struct RouterContextParamTests {

    private func captureWarnings(_ body: () -> Void) -> [String] {
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    @Test("declared param returns its value without warning")
    @MainActor
    func declaredParamNoWarn() {
        let ctx = RouterContext(path: "/users/42", params: ["id": "42"])
        var value: String?
        let warnings = captureWarnings { value = ctx.param("id") }
        #expect(value == "42")
        #expect(warnings.isEmpty)
    }

    @Test("undeclared param returns \"\" and warns with name, path, declared list, guidance")
    @MainActor
    func undeclaredParamWarns() {
        let ctx = RouterContext(path: "/users/42", params: ["id": "42"])
        var value: String?
        let warnings = captureWarnings { value = ctx.param("userId") }
        #expect(value == "")
        #expect(warnings.count == 1)
        let msg = warnings.first ?? ""
        #expect(msg.contains("'userId'"), "names the typo'd param")
        #expect(msg.contains("/users/42"), "names the path so the route is findable")
        #expect(msg.contains("declared params: id"), "lists what IS declared")
        #expect(msg.contains(":param"), "points at the pattern syntax to fix")
    }

    @Test("empty-params context (notFound-style) says (none) for the declared list")
    @MainActor
    func emptyParamsSaysNone() {
        let ctx = RouterContext(path: "/missing")
        var value: String?
        let warnings = captureWarnings { value = ctx.param("id") }
        #expect(value == "")
        #expect((warnings.first ?? "").contains("declared params: (none)"))
    }

    @Test("declared list is sorted and comma-separated — deterministic for grep")
    @MainActor
    func declaredListSorted() {
        let ctx = RouterContext(path: "/x", params: ["zed": "1", "alpha": "2"])
        let warnings = captureWarnings { _ = ctx.param("nope") }
        #expect((warnings.first ?? "").contains("declared params: alpha, zed"))
    }
}
