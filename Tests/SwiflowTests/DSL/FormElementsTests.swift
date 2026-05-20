import Testing
@testable import Swiflow

@Suite("textarea / select / option element factories")
struct FormElementsTests {

    @Test("textarea with text content writes a text child")
    func textareaWithText() {
        let node = textarea("hello", .attr("rows", 5))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.tag == "textarea")
        #expect(data.attributes["rows"] == "5")
        guard case .text(let body) = data.children.first else {
            Issue.record("expected text child"); return
        }
        #expect(body == "hello")
    }

    @Test("textarea with empty text writes no children")
    func textareaEmpty() {
        let node = textarea("")
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.children.isEmpty)
    }

    @Test("textarea block form")
    func textareaBlock() {
        let node = textarea(.attr("rows", 3)) {
            VNode.text("multi-line")
        }
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.tag == "textarea")
        #expect(data.children.count == 1)
    }

    @Test("select with option children")
    func selectWithOptions() {
        let node = select(.attr("name", "color")) {
            option("Red", .attr("value", "r"))
            option("Blue", .attr("value", "b"))
        }
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.tag == "select")
        #expect(data.attributes["name"] == "color")
        #expect(data.children.count == 2)
    }

    @Test("option carries label as text child + value attribute")
    func optionLabelAndValue() {
        let node = option("Red", .attr("value", "r"))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.tag == "option")
        #expect(data.attributes["value"] == "r")
        guard case .text(let body) = data.children.first else {
            Issue.record("expected text child"); return
        }
        #expect(body == "Red")
    }
}
