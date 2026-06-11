// Tests/SwiflowRouterTests/PathParamDecodingTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RoutePattern percent-decodes captured path params")
struct PathParamDecodingTests {

    @Test func paramCaptureIsPercentDecoded() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/john%20doe")?["id"] == "john doe")
        #expect(p.match("/users/a%2Fb")?["id"] == "a/b")
    }

    @Test func plainParamUnchanged() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/alice")?["id"] == "alice")
    }

    @Test func malformedPercentFallsBackToRaw() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/100%")?["id"] == "100%")
    }

    @Test func wildcardCaptureIsPercentDecodedPerSegment() {
        let p = RoutePattern("/files/*")
        #expect(p.match("/files/my%20dir/a%20b.txt")?["*"] == "my dir/a b.txt")
    }

    @Test func prefixParamCaptureIsDecoded() {
        let p = RoutePattern("/users/:id")
        let m = p.prefixMatch("/users/john%20doe/posts")
        #expect(m?.params["id"] == "john doe")
        #expect(m?.remainder == "/posts")
    }
}
