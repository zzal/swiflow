// Tests/SwiflowTests/ElementFactoryTests.swift
import Testing
@testable import Swiflow

@Suite("element(_:attributes:children:) array factory")
struct ArrayElementFactoryTests {
    @Test("element(_:attributes:children:) applies tag, attributes, style, and children") func buildsElementWithAttributesAndChildren() {
        let node = element("div",
                           attributes: [.class("row"), .style("display", "flex")],
                           children: [text("hi")])
        guard case .element(let data) = node else { Issue.record("not an element"); return }
        #expect(data.tag == "div")
        #expect(data.attributes["class"] == "row")
        #expect(data.style["display"] == "flex")
        #expect(data.children.count == 1)
    }

    @Test("Omitted attributes and children default to empty") func defaultsAreEmpty() {
        let node = element("span")
        guard case .element(let data) = node else { Issue.record("not an element"); return }
        #expect(data.tag == "span")
        #expect(data.attributes.isEmpty)
        #expect(data.children.isEmpty)
    }
}
