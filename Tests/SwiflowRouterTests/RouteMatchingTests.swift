// Tests/SwiflowRouterTests/RouteMatchingTests.swift
import Testing
@testable import SwiflowRouter
import Swiflow

// Helpers — build RouteDefinition with a VNode factory (no Component needed)
private func leaf(_ path: String, result: VNode) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { _ in result })
}

private func leafCapture(_ path: String, into box: UnsafeMutablePointer<RouterContext?>) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { ctx in
        box.pointee = ctx
        return .text("matched")
    })
}

@MainActor
@Suite("matchRoutes")
struct RouteMatchingTests {

    @Test("flat route matches exact path")
    func flatRouteMatchesExactPath() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/about") == .text("about"))
    }

    @Test("flat route returns nil on no match")
    func flatRouteNoMatch() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/contact") == nil)
    }

    @Test("first match wins")
    func firstMatchWins() {
        let routes = [
            leaf("/page", result: .text("first")),
            leaf("/page", result: .text("second")),
        ]
        #expect(matchRoutes(routes, path: "/page") == .text("first"))
    }

    @Test("param captured in RouterContext")
    func paramCapturedInContext() {
        var captured: RouterContext? = nil
        let route = leafCapture("/users/:id", into: &captured)
        _ = matchRoutes([route], path: "/users/42")
        #expect(captured?.params["id"] == "42")
    }

    @Test("query string parsed into RouterContext.query")
    func queryStringParsed() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift&page=2")
        #expect(captured?.query["q"] == "swift")
        #expect(captured?.query["page"] == "2")
    }

    @Test("query string stripped before pattern matching")
    func queryStringDoesNotBreakMatch() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/about?utm=foo") != nil)
    }

    @Test("nested route matches child path")
    func nestedRouteMatchesChild() {
        let userList = leaf("/", result: .text("list"))
        let userDetail = leaf("/:id", result: .text("detail"))
        let usersGroup = RouteDefinition(
            pattern: RoutePattern("/users"),
            factory: { _ in .text("") },
            children: [userList, userDetail]
        )
        #expect(matchRoutes([usersGroup], path: "/users") == .text("list"))
        #expect(matchRoutes([usersGroup], path: "/users/42") == .text("detail"))
    }

    @Test("nested params merged with parent params")
    func nestedParamsMerged() {
        var captured: RouterContext? = nil
        let child = RouteDefinition(pattern: RoutePattern("/:repoId"), factory: { ctx in
            captured = ctx
            return .text("repo")
        })
        let parent = RouteDefinition(
            pattern: RoutePattern("/orgs/:org"),
            factory: { _ in .text("") },
            children: [child]
        )
        _ = matchRoutes([parent], path: "/orgs/apple/myrepo")
        #expect(captured?.params["org"] == "apple")
        #expect(captured?.params["repoId"] == "myrepo")
    }

    @Test("wildcard catch-all route matches any path")
    func wildcardCatchAll() {
        let routes = [
            leaf("/about", result: .text("about")),
            leaf("*", result: .text("404")),
        ]
        #expect(matchRoutes(routes, path: "/anything") == .text("404"))
    }

    @Test("returns nil when no route matches (no catch-all)")
    func returnsNilForUnmatchedPath() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/missing") == nil)
    }
}
