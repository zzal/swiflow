// Tests/SwiflowUITests/TextLinkTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@Suite("TextLink")
@MainActor
struct TextLinkTests {
    @Test("TextLink renders <a> with the sw-link class and the given href") func rendersAnchor() {
        let a = elementOf(TextLink("Docs", href: "https://example.com/docs"))!
        #expect(a.tag == "a")
        #expect(a.attributes["class"] == "sw-link")
        #expect(a.attributes["href"] == "https://example.com/docs")
    }

    @Test("label text renders as the anchor's child") func rendersLabelText() {
        let a = elementOf(TextLink("Docs", href: "https://example.com"))!
        #expect(a.children.count == 1)
        if case .text(let t) = a.children[0] { #expect(t == "Docs") } else { Issue.record("no text child") }
    }

    @Test("a javascript: href is scrubbed by URLSanitizer, not passed through raw") func sanitizesJavascriptHref() {
        let raw = "javascript:alert(1)"
        let a = elementOf(TextLink("Danger", href: raw))!
        #expect(a.attributes["href"] != raw)
    }

    @Test("external: true adds target=_blank and rel=noopener noreferrer") func externalAddsSafeNewTabAttrs() {
        let a = elementOf(TextLink("Report", href: "https://example.com", external: true))!
        #expect(a.attributes["target"] == "_blank")
        #expect(a.attributes["rel"] == "noopener noreferrer")
    }

    @Test("external: false (the default) adds neither target nor rel") func nonExternalAddsNoNewTabAttrs() {
        let a = elementOf(TextLink("Docs", href: "https://example.com"))!
        #expect(a.attributes["target"] == nil)
        #expect(a.attributes["rel"] == nil)
    }

    @Test("the children overload renders arbitrary content instead of a plain label") func childrenOverloadRendersContent() {
        let a = elementOf(TextLink(href: "https://example.com") {
            text("Learn ")
            span(.class("emphasis")) { text("more") }
        })!
        #expect(a.tag == "a")
        #expect(a.attributes["href"] == "https://example.com")
        #expect(a.children.count == 2)
    }

    @Test("caller class merges with sw-link instead of clobbering it") func callerClassMerges() {
        let a = elementOf(TextLink("Docs", href: "https://example.com", .class("mine")))!
        #expect(a.attributes["class"] == "sw-link mine")
    }

    @Test("caller attributes merge onto the anchor") func callerAttributesMerge() {
        let a = elementOf(TextLink("Docs", href: "https://example.com", .attr("data-testid", "docs-link")))!
        #expect(a.attributes["data-testid"] == "docs-link")
    }
}
