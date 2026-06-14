// Tests/SwiflowUITests/TextFieldTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .value / .on(.blur) paths
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

// root div -> label (child 0) -> the <input> among the label's children.
@MainActor private func inputOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
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

@Suite("TextField")
@MainActor
struct TextFieldTests {
    private let unused = Binding<String>(get: { "" }, set: { _ in })

    @Test("renders a labelled native input with field chrome and no error by default") func rendersChrome() {
        let node = building { TextField("Name", text: unused) }
        let root = el(node)!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let input = inputOf(node)!
        #expect(input.tag == "input")
        #expect(input.attributes["type"] == "text")
        #expect(input.attributes["aria-invalid"] == "false")
        #expect(allText(node).contains("Name"))     // label text rendered
        #expect(errorOf(node) == nil)               // no error node when error == nil
    }

    @Test("type maps to the native input type") func typeMaps() {
        let input = inputOf(building { TextField("Email", text: unused, type: .email) })!
        #expect(input.attributes["type"] == "email")
    }

    @Test("size sets the field modifier class") func sizeModifier() {
        let root = el(building { TextField("X", text: unused, size: .lg) })!
        #expect(root.attributes["class"] == "sw-field sw-field--lg")
    }

    @Test("placeholder and disabled lower to input attributes") func placeholderAndDisabled() {
        let input = inputOf(building { TextField("X", text: unused, placeholder: "you@ex.com", disabled: true) })!
        #expect(input.attributes["placeholder"] == "you@ex.com")
        #expect(input.attributes["disabled"] == "")   // presence-only boolean attr
    }

    @Test("an error renders a role=alert message and sets aria-invalid on the input") func errorChrome() {
        let node = building { TextField("Email", text: unused, error: "Required") }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
        let err = errorOf(node)!
        #expect(err.attributes["role"] == "alert")
        #expect(allText(.element(err)) == "Required")
    }

    @Test("caller attributes and class land on the input and apply last") func callerAttributesOnInput() {
        let input = inputOf(building { TextField("X", text: unused, .attr("autocomplete", "email"), .class("mine")) })!
        #expect(input.attributes["autocomplete"] == "email")
        #expect(input.attributes["class"] == "mine")
    }

    @Test("the value binding reflects on render and writes back on input") func valueBindingRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var stored = "alpha"
        let binding = Binding<String>(get: { stored }, set: { stored = $0 })
        let input = inputOf(TextField("X", text: binding))!
        if case .string(let v)? = input.properties["value"] { #expect(v == "alpha") }
        else { Issue.record("value property not a string") }
        registry.dispatch(id: input.handlers["input"]!.id, event: EventInfo(type: "input", targetValue: "beta"))
        #expect(stored == "beta")
    }

    @Test("Field convenience renders the field's error when touched + invalid") func fieldConvenienceError() {
        var value = ""
        var ctrl = FormController()
        ctrl.touched.insert("email")                 // simulate a blurred field
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("email", vb, cb, .required())
        let node = building { TextField("Email", field: field) }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
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
        let field = Field("email", vb, cb, .required())
        let input = inputOf(TextField("Email", field: field))!
        #expect(ctrl.touched.contains("email") == false)
        registry.dispatch(id: input.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("email"))
    }

    @Test("Field convenience shows no error and aria-invalid=false while untouched, even if invalid") func fieldConvenienceUntouched() {
        var value = ""                               // empty → would fail .required()
        var ctrl = FormController()                  // but NOT touched
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("email", vb, cb, .required())
        let node = building { TextField("Email", field: field) }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "false")
        #expect(errorOf(node) == nil)                // error stays hidden until the field is touched
    }

    @Test("required emits aria-required; default does not") func requiredAriaOnly() {
        #expect(inputOf(building { TextField("X", text: unused, required: true) })!.attributes["aria-required"] == "true")
        #expect(inputOf(building { TextField("X", text: unused) })!.attributes["aria-required"] == nil)
    }

    @Test("field stylesheet is token-driven, error-aware, and brace-balanced") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-field"))
        #expect(css.contains("var(--sw-border)"))
        #expect(css.contains("var(--sw-focus-ring)"))   // focus honors prefers-contrast
        #expect(css.contains("var(--sw-duration)"))     // transition honors reduced-motion
        #expect(css.contains("var(--sw-danger)"))
        #expect(css.contains("[aria-invalid=\"true\"]"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
