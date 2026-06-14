// Tests/SwiflowUITests/ToggleTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .checked / .on(.blur) paths
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

// root div -> label row (child 0) -> the <input> among the label's children.
@MainActor private func checkboxOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
}

@MainActor private func errorOf(_ root: VNode) -> ElementData? {
    guard let r = el(root) else { return nil }
    return r.children.lazy.compactMap { el($0) }.first { $0.tag == "p" }
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

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("Toggle")
@MainActor
struct ToggleTests {
    private let unused = Binding<Bool>(get: { false }, set: { _ in })

    @Test("renders a checkbox row with label beside the control, no error by default") func rendersRow() {
        let node = building { Toggle("Subscribe", isOn: unused) }
        let root = el(node)!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-toggle")
        #expect(el(root.children.first)!.attributes["class"] == "sw-toggle__row")
        let box = checkboxOf(node)!
        #expect(box.tag == "input")
        #expect(box.attributes["type"] == "checkbox")
        #expect(box.attributes["aria-invalid"] == "false")
        #expect(allText(node).contains("Subscribe"))
        #expect(errorOf(node) == nil)
    }

    @Test("checked binding reflects on render and writes back on change") func checkedBindingRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var on = true
        let binding = Binding<Bool>(get: { on }, set: { on = $0 })
        let box = checkboxOf(Toggle("X", isOn: binding))!
        if case .bool(let b)? = box.properties["checked"] { #expect(b == true) }
        else { Issue.record("checked property not a bool") }
        registry.dispatch(id: box.handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: false))
        #expect(on == false)
    }

    @Test("an error sets aria-invalid and renders a role=alert message") func errorChrome() {
        let node = building { Toggle("Accept", isOn: unused, error: "You must accept") }
        #expect(checkboxOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node)!.attributes["role"] == "alert")
        #expect(allText(node).contains("You must accept"))
    }

    @Test("disabled and required lower to the expected attributes") func disabledAndRequired() {
        let box = checkboxOf(building { Toggle("X", isOn: unused, required: true, disabled: true) })!
        #expect(box.attributes["disabled"] == "")
        #expect(box.attributes["aria-required"] == "true")
    }

    @Test("caller attributes and class land on the checkbox") func callerAttributesOnCheckbox() {
        let box = checkboxOf(building { Toggle("X", isOn: unused, .attr("name", "subscribe"), .class("mine")) })!
        #expect(box.attributes["name"] == "subscribe")
        #expect(box.attributes["class"] == "mine")
    }

    @Test("Field convenience renders the error when touched + invalid") func fieldConvenienceError() {
        var value = false
        var ctrl = FormController()
        ctrl.touched.insert("terms")
        let vb = Binding<Bool>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("terms", vb, cb, .custom("Required") { $0 })   // valid only when true
        let node = building { Toggle("Accept", field: field) }
        #expect(checkboxOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
    }

    @Test("Field convenience wires blur to markTouched") func fieldConvenienceBlurMarksTouched() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = false
        var ctrl = FormController()
        let vb = Binding<Bool>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("terms", vb, cb, .custom("Required") { $0 })
        let box = checkboxOf(Toggle("Accept", field: field))!
        #expect(ctrl.touched.contains("terms") == false)
        registry.dispatch(id: box.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("terms"))
    }
}
