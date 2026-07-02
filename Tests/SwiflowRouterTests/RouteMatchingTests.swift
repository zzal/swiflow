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

    @Test("bare query flag (no `=`) maps to the empty string")
    func bareQueryFlagMapsToEmptyString() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?debug&q=swift")
        #expect(captured?.query["debug"] == "")
        #expect(captured?.query["q"] == "swift")
    }

    @Test("query string stripped before pattern matching")
    func queryStringDoesNotBreakMatch() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/about?utm=foo") != nil)
    }

    @Test("query percent-decoding: ASCII space")
    func queryPercentDecodingASCIISpace() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%20world")
        #expect(captured?.query["q"] == "hello world")
    }

    @Test("query percent-decoding: multi-byte UTF-8")
    func queryPercentDecodingUTF8() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=caf%C3%A9")
        #expect(captured?.query["q"] == "café")
    }

    @Test("query percent-decoding: encoded plus round-trip")
    func queryPercentDecodingEncodedPlus() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift%20%2B%20wasm")
        #expect(captured?.query["q"] == "swift + wasm")
    }

    @Test("query percent-decoding: lowercase hex digits")
    func queryPercentDecodingLowercaseHex() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=%c3%a9")
        #expect(captured?.query["q"] == "é")
    }

    @Test("query percent-decoding: encoded key")
    func queryPercentDecodingEncodedKey() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?caf%C3%A9=val")
        #expect(captured?.query["café"] == "val")
    }

    // Malformed-escape fallback: Foundation's removingPercentEncoding returns
    // nil on a lone trailing '%', and splitQuery falls back to the literal
    // substring via `?? String(parts[1])`. The stdlib decoder in Task 2 must
    // match this behavior so this assertion survives the swap.
    @Test("query percent-decoding: lone trailing percent falls back to literal")
    func queryPercentDecodingLoneTrailingPercent() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%")
        #expect(captured?.query["q"] == "hello%")
    }

    // Bad-hex fallback: '%2G' is not a valid percent escape; both Foundation
    // and the Task 2 stdlib decoder return nil, and splitQuery falls back
    // to the literal substring.
    @Test("query percent-decoding: invalid hex falls back to literal")
    func queryPercentDecodingInvalidHex() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%2G")
        #expect(captured?.query["q"] == "hello%2G")
    }

    // Deliberate semantic lock-in: RFC 3986 leaves '+' as a literal '+'.
    // WHATWG URLSearchParams + HTML form encoding translate '+' to space;
    // Swiflow follows Foundation (RFC 3986). If a future change wants to
    // adopt WHATWG semantics, this assertion will fail loudly and the
    // change will be deliberate.
    @Test("query: literal plus stays literal (RFC 3986, not WHATWG)")
    func queryPlusStaysLiteral() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift+wasm")
        #expect(captured?.query["q"] == "swift+wasm")
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
