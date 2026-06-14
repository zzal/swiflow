// Tests/SwiflowUITests/CheckboxTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func boxOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
}

@MainActor private func rowOf(_ root: VNode) -> ElementData? { el(el(root)?.children.first) }

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

@Suite("Checkbox")
@MainActor
struct CheckboxTests {
    private let unused = Binding<Bool>(get: { false }, set: { _ in })

    @Test("renders a native checkbox with the label beside it (no switch role)") func rendersCheckbox() {
        let node = building { Checkbox("Select all", isOn: unused) }
        #expect(el(node)!.attributes["class"] == "sw-check")
        #expect(rowOf(node)!.attributes["class"] == "sw-check__row")
        let box = boxOf(node)!
        #expect(box.attributes["type"] == "checkbox")
        #expect(box.attributes["role"] == nil)               // plain checkbox, unlike Toggle's role=switch
        #expect(box.attributes["aria-invalid"] == "false")
        #expect(allText(node).contains("Select all"))
        #expect(errorOf(node) == nil)
    }

    @Test("checked binding reflects on render and writes back on change") func checkedRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var on = true
        let binding = Binding<Bool>(get: { on }, set: { on = $0 })
        let box = boxOf(Checkbox("X", isOn: binding))!
        if case .bool(let b)? = box.properties["checked"] { #expect(b == true) }
        else { Issue.record("checked property not a bool") }
        registry.dispatch(id: box.handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: false))
        #expect(on == false)
    }

    @Test("an error sets aria-invalid and renders a role=alert message") func errorChrome() {
        let node = building { Checkbox("Accept", isOn: unused, error: "You must accept") }
        #expect(boxOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node)!.attributes["role"] == "alert")
        #expect(allText(node).contains("You must accept"))
    }

    @Test("disabled and required lower to attributes + the row modifier") func disabledAndRequired() {
        let node = building { Checkbox("X", isOn: unused, required: true, disabled: true) }
        let box = boxOf(node)!
        #expect(box.attributes["disabled"] == "")
        #expect(box.attributes["aria-required"] == "true")
        #expect(rowOf(node)!.attributes["class"] == "sw-check__row sw-check__row--disabled")
    }

    @Test("caller attributes coexist with the binding (change still writes back)") func callerAttrsKeepBinding() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var on = false
        let binding = Binding<Bool>(get: { on }, set: { on = $0 })
        let box = boxOf(Checkbox("X", isOn: binding, .attr("name", "n"), .class("mine")))!
        #expect(box.attributes["name"] == "n")
        #expect(box.attributes["class"] == "mine")
        registry.dispatch(id: box.handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: true))
        #expect(on == true)
    }

    @Test("Field convenience renders the error when touched + invalid, and wires blur") func fieldConvenience() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = false
        var ctrl = FormController()
        ctrl.touched.insert("terms")
        let vb = Binding<Bool>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("terms", vb, cb, .custom("Required") { $0 })
        let node = Checkbox("Accept", field: field)
        #expect(boxOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
        registry.dispatch(id: boxOf(node)!.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("terms"))
    }

    @Test("checkbox stylesheet uses accent-color and the error outline") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-check"))
        #expect(css.contains("accent-color: var(--sw-accent)"))
        #expect(css.contains(".sw-check input[aria-invalid=\"true\"]"))
    }
}
