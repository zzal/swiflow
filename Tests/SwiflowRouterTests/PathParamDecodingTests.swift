// Tests/SwiflowRouterTests/PathParamDecodingTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RoutePattern percent-decodes captured path params")
struct PathParamDecodingTests {

    @Test("Captured :param values are percent-decoded, including encoded slashes") func paramCaptureIsPercentDecoded() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/john%20doe")?["id"] == "john doe")
        #expect(p.match("/users/a%2Fb")?["id"] == "a/b")
    }

    @Test("A param with no percent escapes is captured verbatim") func plainParamUnchanged() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/alice")?["id"] == "alice")
    }

    @Test("A malformed percent escape falls back to the raw segment instead of failing") func malformedPercentFallsBackToRaw() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/100%")?["id"] == "100%")
    }

    @Test("Wildcard captures decode each segment while keeping the / separators") func wildcardCaptureIsPercentDecodedPerSegment() {
        let p = RoutePattern("/files/*")
        #expect(p.match("/files/my%20dir/a%20b.txt")?["*"] == "my dir/a b.txt")
    }

    @Test("prefixMatch decodes captured params and preserves the remainder") func prefixParamCaptureIsDecoded() {
        let p = RoutePattern("/users/:id")
        let m = p.prefixMatch("/users/john%20doe/posts")
        #expect(m?.params["id"] == "john doe")
        #expect(m?.remainder == "/posts")
    }
}
