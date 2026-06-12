// Tests/SwiflowTests/DSL/PostfixURLSanitizerTests.swift
import Testing
@testable import Swiflow

@Suite
@MainActor
struct PostfixURLSanitizerTests {

    private func attributes(of node: VNode) -> [String: String] {
        guard case .element(let data) = node else { return [:] }
        return data.attributes
    }

    @Test("Postfix .attr drops a javascript: href like the prefix path does") func postfixAttrDropsJavascriptHref() {
        let node = div { VNode.text("x") }.attr("href", "javascript:alert(1)")
        #expect(attributes(of: node)["href"] == nil,
                "postfix .attr must enforce the same allowlist as the prefix path")
    }

    @Test("Postfix .attr keeps an https: href") func postfixAttrKeepsSafeHref() {
        let node = div { VNode.text("x") }.attr("href", "https://example.com")
        #expect(attributes(of: node)["href"] == "https://example.com")
    }

    @Test("URL sanitizing matches the attribute name case-insensitively") func postfixAttrIsCaseInsensitiveOnTheName() {
        let node = div { VNode.text("x") }.attr("HREF", "javascript:alert(1)")
        #expect(attributes(of: node)["HREF"] == nil)
    }

    @Test("Non-URL attributes pass through unsanitized") func postfixAttrLeavesNonURLAttributesAlone() {
        let node = div { VNode.text("x") }.attr("title", "javascript:not-a-url-slot")
        #expect(attributes(of: node)["title"] == "javascript:not-a-url-slot")
    }
}
