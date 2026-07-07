// Tests/SwiflowRouterTests/RouterRootNotFoundTests.swift
//
// Audit IV Wave-1 #3: the 404 was a hardcoded dev literal that shipped to
// production (`Route("*")` works at the matcher but is undocumented and
// unused by every example). RouterRoot now takes a trailing
// `notFound: { ctx in NotFoundPage(path: ctx.path) }` closure — the
// fallback decision itself is a pure static (RouterRoot isn't
// host-constructible: its init reads the browser URL), tested here.
import Testing
import Swiflow
@testable import SwiflowRouter

@Suite("RouterRoot notFound fallback")
struct RouterRootNotFoundTests {

    /// VNode has no text accessor — unwrap the .text case.
    private func text(of node: VNode) -> String? {
        if case .text(let s) = node { return s }
        return nil
    }

    @Test("a matched route always wins, even with a notFound closure present")
    @MainActor
    func matchedWins() {
        let matched = VNode.text("the page")
        let out = RouterRoot.resolveContent(
            matched: matched,
            path: "/here",
            notFound: { _ in VNode.text("nope") }
        )
        #expect(text(of: out) == "the page")
    }

    @Test("an unmatched path renders the notFound closure with the path in context")
    @MainActor
    func notFoundClosureReceivesPath() {
        let out = RouterRoot.resolveContent(
            matched: nil,
            path: "/missing/42",
            notFound: { ctx in
                #expect(ctx.path == "/missing/42")
                #expect(ctx.params.isEmpty, "no route matched — there are no captures")
                #expect(ctx.query.isEmpty)
                return VNode.text("custom 404 for \(ctx.path)")
            }
        )
        #expect(text(of: out) == "custom 404 for /missing/42")
    }

    @Test("without a notFound closure, today's default text remains")
    @MainActor
    func defaultTextPreserved() {
        let out = RouterRoot.resolveContent(matched: nil, path: "/typo", notFound: nil)
        #expect(text(of: out)?.contains("404") == true)
        #expect(text(of: out)?.contains("/typo") == true,
                "the path stays in the default so a dev screenshot is diagnosable")
    }
}
