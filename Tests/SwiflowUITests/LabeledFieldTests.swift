import Testing
import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode) -> ElementData? {
    if case .element(let d) = node { return d }
    return nil
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                        return s
    case .element(let d):                     return d.children.map(allText).joined()
    case .fragment(let xs):                   return xs.map(allText).joined()
    case .environmentOverride(_, let child):  return allText(child)
    default:                                  return ""
    }
}

@Suite("LabeledField")
@MainActor
struct LabeledFieldTests {
    @Test("emits the full chrome: root div, wrapping label, label line, control slot") func structure() {
        let node = LabeledField("Name") { element("input", attributes: [.attr("type", "text")]) }
        let root = el(node)!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let label = el(root.children[0])!
        #expect(label.tag == "label")
        #expect(label.attributes["class"] == "sw-field__label")
        let line = el(label.children[0])!
        #expect(line.attributes["class"] == "sw-field__label-line")
        let labelText = el(line.children[0])!
        #expect(labelText.attributes["class"] == "sw-field__label-text")
        #expect(allText(line.children[0]) == "Name")
        let control = el(label.children[1])!
        #expect(control.tag == "input")
    }

    @Test("vertical (default) has no --h class; horizontal adds it on the root") func layoutClass() {
        let v = el(LabeledField("A") { element("input", attributes: []) })!
        #expect(v.attributes["class"]?.contains("sw-field--h") == false)
        let h = el(LabeledField("A", layout: .horizontal) { element("input", attributes: []) })!
        #expect(h.attributes["class"] == "sw-field sw-field--md sw-field--h")
    }

    @Test("prefix/suffix render as adornment spans, in order, only when given") func adornments() {
        let plain = el(LabeledField("A") { element("input", attributes: []) })!
        let plainLine = el(el(plain.children[0])!.children[0])!
        #expect(plainLine.children.count == 1)   // just the label text

        let both = el(LabeledField("A", prefix: text("P"), suffix: text("S")) { element("input", attributes: []) })!
        let line = el(el(both.children[0])!.children[0])!
        #expect(line.children.count == 3)
        #expect(el(line.children[0])!.attributes["class"] == "sw-field__label-prefix")
        #expect(allText(line.children[0]) == "P")
        #expect(el(line.children[1])!.attributes["class"] == "sw-field__label-text")
        #expect(el(line.children[2])!.attributes["class"] == "sw-field__label-suffix")
        #expect(allText(line.children[2]) == "S")
    }

    @Test("error renders the standard role=alert node after the label") func error() {
        let root = el(LabeledField("A", error: "Required") { element("input", attributes: []) })!
        #expect(root.children.count == 2)
        let err = el(root.children[1])!
        #expect(err.attributes["class"] == "sw-field-error")
        #expect(err.attributes["role"] == "alert")
        #expect(allText(root.children[1]) == "Required")
    }

    @Test("size sets the root modifier; caller attributes/classes merge onto the root") func sizeAndAttrs() {
        let root = el(LabeledField("A", size: .lg, .class("mine"), .attr("data-x", "1")) {
            element("input", attributes: [])
        })!
        #expect(root.attributes["class"] == "sw-field sw-field--lg mine")
        #expect(root.attributes["data-x"] == "1")
    }
}
