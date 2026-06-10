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

    @Test func postfixAttrDropsJavascriptHref() {
        let node = div { VNode.text("x") }.attr("href", "javascript:alert(1)")
        #expect(attributes(of: node)["href"] == nil,
                "postfix .attr must enforce the same allowlist as the prefix path")
    }

    @Test func postfixAttrKeepsSafeHref() {
        let node = div { VNode.text("x") }.attr("href", "https://example.com")
        #expect(attributes(of: node)["href"] == "https://example.com")
    }

    @Test func postfixAttrIsCaseInsensitiveOnTheName() {
        let node = div { VNode.text("x") }.attr("HREF", "javascript:alert(1)")
        #expect(attributes(of: node)["HREF"] == nil)
    }

    @Test func postfixAttrLeavesNonURLAttributesAlone() {
        let node = div { VNode.text("x") }.attr("title", "javascript:not-a-url-slot")
        #expect(attributes(of: node)["title"] == "javascript:not-a-url-slot")
    }
}
