// Tests/SwiflowRouterTests/RoutePatternTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RoutePattern")
struct RoutePatternTests {

    @Test("static segment matches exactly")
    func staticSegmentMatchesExactly() {
        let p = RoutePattern("/about")
        #expect(p.match("/about") != nil)
        #expect(p.match("/about") == [:])
    }

    @Test("static segment does not match different path")
    func staticSegmentNoMatch() {
        let p = RoutePattern("/about")
        #expect(p.match("/contact") == nil)
    }

    @Test("param segment captures value")
    func paramSegmentCaptures() {
        let p = RoutePattern("/users/:id")
        let result = p.match("/users/42")
        #expect(result == ["id": "42"])
    }

    @Test("multiple param segments captured")
    func multipleParams() {
        let p = RoutePattern("/users/:userId/posts/:postId")
        let result = p.match("/users/1/posts/99")
        #expect(result == ["userId": "1", "postId": "99"])
    }

    @Test("wildcard captures remaining path")
    func wildcardCapturesRemaining() {
        let p = RoutePattern("*")
        let result = p.match("/anything/goes/here")
        #expect(result?["*"] == "anything/goes/here")
    }

    @Test("trailing slash normalized on input")
    func trailingSlashNormalized() {
        let p = RoutePattern("/about")
        #expect(p.match("/about/") != nil)
    }

    @Test("root path matches /")
    func rootPathMatches() {
        let p = RoutePattern("/")
        #expect(p.match("/") != nil)
        #expect(p.match("") != nil)
    }

    @Test("prefixMatch returns remainder and params")
    func prefixMatchReturnsRemainder() {
        let p = RoutePattern("/users")
        let result = p.prefixMatch("/users/42")
        #expect(result?.params == [:])
        #expect(result?.remainder == "/42")
    }

    @Test("prefixMatch with param segment")
    func prefixMatchWithParam() {
        let p = RoutePattern("/orgs/:org")
        let result = p.prefixMatch("/orgs/apple/repos")
        #expect(result?.params == ["org": "apple"])
        #expect(result?.remainder == "/repos")
    }

    @Test("prefixMatch returns nil when prefix does not match")
    func prefixMatchNoMatch() {
        let p = RoutePattern("/users")
        #expect(p.prefixMatch("/posts/1") == nil)
    }

    @Test("query string stripped before matching")
    func queryStringStripped() {
        let p = RoutePattern("/search")
        #expect(p.match("/search?q=swift") != nil)
    }
}
