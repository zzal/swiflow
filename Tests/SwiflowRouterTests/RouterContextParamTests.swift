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

    @Test("typed access parses Int, Double, and Bool")
    @MainActor
    func typedSuccess() {
        let ctx = RouterContext(
            path: "/p",
            params: ["n": "42", "ratio": "2.5", "draft": "true"]
        )
        var n: Int?
        var ratio: Double?
        var draft: Bool?
        let warnings = captureWarnings {
            n = ctx.param("n", as: Int.self)
            ratio = ctx.param("ratio", as: Double.self)
            draft = ctx.param("draft", as: Bool.self)
        }
        #expect(n == 42)
        #expect(ratio == 2.5)
        #expect(draft == true)
        #expect(warnings.isEmpty)
    }

    @Test("declared-but-unparseable value is a silent nil — URLs are user input")
    @MainActor
    func unparseableIsSilentNil() {
        let ctx = RouterContext(path: "/users/abc", params: ["id": "abc"])
        var value: Int? = 0
        let warnings = captureWarnings { value = ctx.param("id", as: Int.self) }
        #expect(value == nil)
        #expect(warnings.isEmpty, "parse failure is runtime input, not a programmer error")
    }

    @Test("typed access to an undeclared name returns nil AND warns")
    @MainActor
    func typedUndeclaredWarns() {
        let ctx = RouterContext(path: "/users/42", params: ["id": "42"])
        var value: Int? = 0
        let warnings = captureWarnings { value = ctx.param("userId", as: Int.self) }
        #expect(value == nil)
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("'userId'"))
    }

    @Test("accessors through a real matched route tree — nested namespace merges parent params")
    @MainActor
    func integrationThroughMatchRoutes() {
        var org: String?
        var repoId: Int?
        let child = RouteDefinition(pattern: RoutePattern("/:id")) { ctx in
            org = ctx.param("org")
            repoId = ctx.param("id", as: Int.self)
            return .text("repo")
        }
        let parent = RouteDefinition(
            pattern: RoutePattern("/orgs/:org"),
            factory: { _ in .text("") },
            children: [child]
        )
        let warnings = captureWarnings {
            _ = matchRoutes([parent], path: "/orgs/apple/7")
        }
        #expect(org == "apple", "ancestor params merge into the leaf context")
        #expect(repoId == 7)
        #expect(warnings.isEmpty, "declared access through the real matcher never warns")
    }

    @Test("wildcard capture reads through param(\"*\")")
    @MainActor
    func wildcardParam() {
        var rest: String?
        let route = RouteDefinition(pattern: RoutePattern("/files/*")) { ctx in
            rest = ctx.param("*")
            return .text("files")
        }
        let warnings = captureWarnings {
            _ = matchRoutes([route], path: "/files/a/b/c")
        }
        #expect(rest == "a/b/c")
        #expect(warnings.isEmpty)
    }
}
