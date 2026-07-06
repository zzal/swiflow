// Tests/SwiflowTests/TypedAttributeTests.swift
//
// Typed attribute helpers (Wave 3 #1): named `Attribute` factories for the
// handful of attributes every app reaches for, replacing typo-prone
// `.attr("href", …)` stringly access. Pure core → host-testable at the
// element level: build a VNode, then assert the folded `ElementData.attributes`.

import Testing
@testable import Swiflow

@Suite("Typed attribute helpers")
struct TypedAttributeTests {

    /// The folded HTML attributes of an element VNode.
    private func attrs(_ node: VNode) -> [String: String] {
        guard case .element(let data) = node else {
            Issue.record("expected an element VNode")
            return [:]
        }
        return data.attributes
    }

    @Test(".href sets the href attribute")
    func hrefSetsHref() {
        #expect(attrs(link("Home", .href("/docs")))["href"] == "/docs")
    }

    @Test(".newTab() emits target=_blank AND rel=noopener noreferrer together")
    func newTabSetsSafePair() {
        let a = attrs(link("External", .href("https://example.com"), .newTab()))
        #expect(a["href"] == "https://example.com")
        #expect(a["target"] == "_blank")
        #expect(a["rel"] == "noopener noreferrer",
                "newTab must pair _blank with the reverse-tabnabbing/referrer guard")
    }

    @Test("img .src / .alt / .width / .height")
    func imgMediaAttrs() {
        let a = attrs(img(.src("/logo.png"), .alt("Logo"), .width(120), .height(48)))
        #expect(a["src"] == "/logo.png")
        #expect(a["alt"] == "Logo")
        #expect(a["width"] == "120")
        #expect(a["height"] == "48")
    }

    @Test("input .type(InputType) / .placeholder / .name")
    func inputFormAttrs() {
        let a = attrs(input(.type(.email), .placeholder("you@example.com"), .name("email")))
        #expect(a["type"] == "email")
        #expect(a["placeholder"] == "you@example.com")
        #expect(a["name"] == "email")
    }

    @Test("InputType.htmlValue: plain, dashed, and custom")
    func inputTypeMapping() {
        #expect(InputType.text.htmlValue == "text")
        #expect(InputType.password.htmlValue == "password")
        #expect(InputType.checkbox.htmlValue == "checkbox")
        #expect(InputType.datetimeLocal.htmlValue == "datetime-local",
                "camelCase case must render as the kebab-case HTML value")
        #expect(InputType.custom("image").htmlValue == "image")
        // …and through the .type(_:) helper onto the element:
        #expect(attrs(input(.type(.datetimeLocal)))["type"] == "datetime-local")
        #expect(attrs(input(.type(.custom("image"))))["type"] == "image")
    }

    @Test(".for associates a <label> with its control")
    func labelFor() {
        #expect(attrs(element("label", attributes: [.for("email")]))["for"] == "email")
    }

    @Test(".title / .target / .rel standalone")
    func miscAttrs() {
        #expect(attrs(link("x", .title("Tooltip")))["title"] == "Tooltip")
        #expect(attrs(link("x", .target("_self")))["target"] == "_self")
        #expect(attrs(link("x", .rel("stylesheet")))["rel"] == "stylesheet")
    }

    @Test("typed helpers compose with .class, .attr, and each other")
    func composesWithOtherModifiers() {
        let a = attrs(link("Docs",
                           .href("/docs"),
                           .class("nav-link"),
                           .attr("aria-current", "page")))
        #expect(a["href"] == "/docs")
        #expect(a["class"] == "nav-link")
        #expect(a["aria-current"] == "page")
    }
}
