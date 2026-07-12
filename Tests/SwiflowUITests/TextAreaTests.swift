// Tests/SwiflowUITests/TextAreaTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .value / .on(.blur) paths
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

// root div -> label (child 0) -> the <textarea> among the label's children.
@MainActor private func controlOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "textarea" }
}

// root div -> the error <p> sibling, if present.
@MainActor private func errorOf(_ root: VNode) -> ElementData? {
    guard let r = el(root) else { return nil }
    return r.children.lazy.compactMap { el($0) }.first { $0.tag == "p" }
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):            return s
    case .element(let d):         return d.children.map(allText).joined()
    case .fragment(let xs):       return xs.map(allText).joined()
    case .environmentOverride(_, let child): return allText(child)
    default:                      return ""
    }
}

// .value / .on(.blur) register through the ambient handler registry (set during
// render); provide one for direct construction.
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("TextArea")
@MainActor
struct TextAreaTests {
    private let unused = Binding<String>(get: { "" }, set: { _ in })

    @Test("renders a labelled native textarea with field chrome and no error by default") func rendersFieldChromeWithTextarea() {
        let node = building { TextArea("Bio", text: unused) }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let ta = controlOf(node)
        #expect(ta != nil)
        #expect(ta?.tag == "textarea")
        #expect(ta?.attributes["rows"] == "3")
        #expect(allText(node).contains("Bio"))
        #expect(errorOf(node) == nil)
    }

    @Test("rows, placeholder, and size lower to the textarea/root") func rowsPlaceholderAndSize() {
        let ta = controlOf(building { TextArea("Bio", text: unused, rows: 6, placeholder: "Tell us about you…") })!
        #expect(ta.attributes["rows"] == "6")
        #expect(ta.attributes["placeholder"] == "Tell us about you…")

        let root = el(building { TextArea("Bio", text: unused, size: .lg) })!
        #expect(root.attributes["class"] == "sw-field sw-field--lg")
    }

    @Test("an error renders a role=alert message and sets aria-invalid on the textarea") func errorRendersAlertAndAriaInvalid() {
        let node = building { TextArea("Bio", text: unused, error: "Required") }
        #expect(controlOf(node)!.attributes["aria-invalid"] == "true")
        let err = errorOf(node)!
        #expect(err.attributes["role"] == "alert")
        #expect(allText(.element(err)) == "Required")

        let clean = building { TextArea("Bio", text: unused) }
        #expect(controlOf(clean)!.attributes["aria-invalid"] == "false")
        #expect(errorOf(clean) == nil)
    }

    @Test("disabled sets the disabled attribute on the textarea") func disabledSetsAttribute() {
        let ta = controlOf(building { TextArea("Bio", text: unused, disabled: true) })!
        #expect(ta.attributes["disabled"] == "")   // presence-only boolean attr
    }

    @Test("caller attributes land on the textarea and apply last") func callerAttributesLandOnTextarea() {
        let ta = controlOf(building { TextArea("Bio", text: unused, .attr("name", "bio")) })!
        #expect(ta.attributes["name"] == "bio")
    }

    @Test("Field convenience renders the field's error when touched + invalid") func fieldConvenienceError() {
        var value = ""
        var ctrl = FormController()
        ctrl.touched.insert("bio")                 // simulate a blurred field
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("bio", vb, cb, .required())
        let node = building { TextArea("Bio", field: field) }
        #expect(controlOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
    }

    @Test("Field convenience wires blur to markTouched") func fieldConvenienceBlurMarksTouched() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = ""
        var ctrl = FormController()
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("bio", vb, cb, .required())
        let ta = controlOf(TextArea("Bio", field: field))!
        #expect(ctrl.touched.contains("bio") == false)
        registry.dispatch(id: ta.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("bio"))
    }
}
