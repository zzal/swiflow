// Tests/SwiflowUITests/TextTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@Suite("Text")
@MainActor
struct TextTests {
    @Test("default renders <p class=\"sw-text sw-text--body\"> with the content") func rendersDefault() {
        let el = elementOf(Text("Hello"))!
        #expect(el.tag == "p")
        #expect(el.attributes["class"] == "sw-text sw-text--body")
        #expect(el.children.count == 1)
        if case .text(let t) = el.children[0] { #expect(t == "Hello") } else { Issue.record("no text child") }
    }

    @Test("title variant renders <h1> with sw-text--title") func titleVariant() {
        let el = elementOf(Text("Title", variant: .title))!
        #expect(el.tag == "h1")
        #expect(el.attributes["class"] == "sw-text sw-text--title")
    }

    @Test("heading variant renders <h2> with sw-text--heading") func headingVariant() {
        let el = elementOf(Text("Heading", variant: .heading))!
        #expect(el.tag == "h2")
        #expect(el.attributes["class"] == "sw-text sw-text--heading")
    }

    @Test("subheading variant renders <h3> with sw-text--subheading") func subheadingVariant() {
        let el = elementOf(Text("Subheading", variant: .subheading))!
        #expect(el.tag == "h3")
        #expect(el.attributes["class"] == "sw-text sw-text--subheading")
    }

    @Test("body variant renders <p> with sw-text--body") func bodyVariant() {
        let el = elementOf(Text("Body", variant: .body))!
        #expect(el.tag == "p")
        #expect(el.attributes["class"] == "sw-text sw-text--body")
    }

    @Test("caption variant renders <p> with sw-text--caption") func captionVariant() {
        let el = elementOf(Text("Caption", variant: .caption))!
        #expect(el.tag == "p")
        #expect(el.attributes["class"] == "sw-text sw-text--caption")
    }

    @Test("label variant renders <span> with sw-text--label") func labelVariant() {
        let el = elementOf(Text("Label", variant: .label))!
        #expect(el.tag == "span")
        #expect(el.attributes["class"] == "sw-text sw-text--label")
    }

    @Test("tag: overrides the element while keeping the variant class") func tagOverride() {
        let el = elementOf(Text("Custom", variant: .title, tag: "h4"))!
        #expect(el.tag == "h4")
        #expect(el.attributes["class"] == "sw-text sw-text--title")
    }

    @Test("weight: .semibold adds sw-text--w-semibold") func explicitWeight() {
        let el = elementOf(Text("Bold", weight: .semibold))!
        #expect(el.attributes["class"] == "sw-text sw-text--body sw-text--w-semibold")
    }

    @Test("weight: nil (the default) adds no weight class") func nilWeight() {
        let el = elementOf(Text("Plain"))!
        #expect(el.attributes["class"] == "sw-text sw-text--body")
    }

    @Test("color: .muted adds sw-text--c-muted") func mutedColor() {
        let el = elementOf(Text("Muted", color: .muted))!
        #expect(el.attributes["class"] == "sw-text sw-text--body sw-text--c-muted")
    }

    @Test("color: .standard (the default) adds no color class") func standardColorEmitsNoClass() {
        let el = elementOf(Text("Standard", color: .standard))!
        #expect(el.attributes["class"] == "sw-text sw-text--body")
    }

    @Test("caller class merges with sw-text instead of clobbering it") func callerClassMerges() {
        let el = elementOf(Text("Hello", .class("mine")))!
        #expect(el.attributes["class"] == "sw-text sw-text--body mine")
    }

    @Test("caller attributes merge onto the element") func callerAttributesMerge() {
        let el = elementOf(Text("Hello", .attr("data-testid", "greeting")))!
        #expect(el.attributes["data-testid"] == "greeting")
    }
}
