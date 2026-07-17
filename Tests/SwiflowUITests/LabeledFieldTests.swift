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

@Suite("fieldRootClasses")
@MainActor
struct FieldRootClassesTests {
    @Test("base + size, no layout or extra classes for vertical") func base() {
        #expect(fieldRootClasses(size: .md, layout: .vertical) == ["sw-field", "sw-field--md"])
    }

    @Test("horizontal and hug append their layout modifiers, in order") func layout() {
        #expect(fieldRootClasses(size: .lg, layout: .horizontal) == ["sw-field", "sw-field--lg", "sw-field--h"])
        #expect(fieldRootClasses(size: .md, layout: .horizontal(labelColumn: .hug))
                == ["sw-field", "sw-field--md", "sw-field--h", "sw-field--h-hug"])
    }

    @Test("extra classes land between the size modifier and the layout modifiers") func extra() {
        #expect(fieldRootClasses(size: .md, layout: .horizontal, extra: ["sw-ac"])
                == ["sw-field", "sw-field--md", "sw-ac", "sw-field--h"])
    }

    @Test("a custom base swaps the class family, still composes with layout") func customBase() {
        #expect(fieldRootClasses(base: "sw-switch", size: .md, layout: .vertical) == ["sw-switch", "sw-switch--md"])
        #expect(fieldRootClasses(base: "sw-radio", size: .lg, layout: .horizontal) == ["sw-radio", "sw-radio--lg", "sw-field--h"])
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

    @Test("vertical has no --h class; horizontal adds it; hug adds the hug modifier") func layoutClass() {
        let v = el(LabeledField("A") { element("input", attributes: []) })!
        #expect(v.attributes["class"]?.contains("sw-field--h") == false)
        // source-compat pins: bare `.horizontal` still exists, means fixed,
        // and emits exactly the pre-hug class string
        #expect(FieldLayout.horizontal == .horizontal(labelColumn: .fixed))
        let h = el(LabeledField("A", layout: .horizontal) { element("input", attributes: []) })!
        #expect(h.attributes["class"] == "sw-field sw-field--md sw-field--h")
        let hug = el(LabeledField("A", layout: .horizontal(labelColumn: .hug)) { element("input", attributes: []) })!
        #expect(hug.attributes["class"] == "sw-field sw-field--md sw-field--h sw-field--h-hug")
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

    @Test("horizontal wraps 2+ control nodes in one .sw-field__controls grid item") func multiNodeControls() {
        // 2 nodes + horizontal: wrapped, so the 2-column grid holds
        let h = el(LabeledField("A", layout: .horizontal) {
            element("input", attributes: [])
            element("span", attributes: [], children: [text("hint")])
        })!
        let hLabel = el(h.children[0])!
        #expect(hLabel.children.count == 2)   // label line + ONE wrapped slot
        let slot = el(hLabel.children[1])!
        #expect(slot.tag == "span")
        #expect(slot.attributes["class"] == "sw-field__controls")
        #expect(slot.children.count == 2)

        // 1 node + horizontal: no wrapper (the built-in controls' DOM, unchanged)
        let single = el(LabeledField("A", layout: .horizontal) { element("input", attributes: []) })!
        #expect(el(el(single.children[0])!.children[1])!.tag == "input")

        // 2 nodes + vertical: never wraps (stacking needs no grid item)
        let v = el(LabeledField("A") {
            element("input", attributes: [])
            element("span", attributes: [], children: [text("hint")])
        })!
        #expect(el(v.children[0])!.children.count == 3)   // line + both nodes
    }
}
