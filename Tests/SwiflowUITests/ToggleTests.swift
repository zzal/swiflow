// Tests/SwiflowUITests/ToggleTests.swift
// Toggle is now a SWITCH (role=switch + track/thumb). The checkbox lives in CheckboxTests.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func inputOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
}

@MainActor private func rowOf(_ root: VNode) -> ElementData? { el(el(root)?.children.first) }

@MainActor private func hasClass(_ root: VNode, _ cls: String) -> Bool {
    guard let r = el(root) else { return false }
    func walk(_ d: ElementData) -> Bool {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return true }
        return d.children.contains { el($0).map(walk) ?? false }
    }
    return walk(r)
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

@Suite("Toggle (switch)")
@MainActor
struct ToggleTests {
    private let unused = Binding<Bool>(get: { false }, set: { _ in })

    @Test("renders a switch: role=switch checkbox + track/thumb, label beside") func rendersSwitch() {
        let node = building { Toggle("Dark mode", isOn: unused) }
        #expect(el(node)!.attributes["class"] == "sw-switch")
        #expect(rowOf(node)!.attributes["class"] == "sw-switch__row")
        let input = inputOf(node)!
        #expect(input.attributes["type"] == "checkbox")
        #expect(input.attributes["role"] == "switch")          // announced as a switch, not a checkbox
        #expect(input.attributes["aria-invalid"] == "false")
        #expect(hasClass(node, "sw-switch__track"))            // the visual track…
        #expect(hasClass(node, "sw-switch__thumb"))            // …and the sliding thumb
        #expect(allText(node).contains("Dark mode"))
        #expect(errorOf(node) == nil)
    }

    @Test("checked binding reflects on render and writes back on change") func checkedRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var on = false
        let binding = Binding<Bool>(get: { on }, set: { on = $0 })
        let input = inputOf(Toggle("X", isOn: binding))!
        if case .bool(let b)? = input.properties["checked"] { #expect(b == false) }
        else { Issue.record("checked property not a bool") }
        registry.dispatch(id: input.handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: true))
        #expect(on == true)
    }

    @Test("an error sets aria-invalid and renders a role=alert message") func errorChrome() {
        let node = building { Toggle("X", isOn: unused, error: "Required") }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node)!.attributes["role"] == "alert")
        #expect(allText(node).contains("Required"))
    }

    @Test("disabled and required lower to attributes + the row modifier") func disabledAndRequired() {
        let node = building { Toggle("X", isOn: unused, required: true, disabled: true) }
        let input = inputOf(node)!
        #expect(input.attributes["disabled"] == "")
        #expect(input.attributes["aria-required"] == "true")
        #expect(rowOf(node)!.attributes["class"] == "sw-switch__row sw-switch__row--disabled")
    }

    @Test("caller attributes and class land on the input") func callerAttributes() {
        let input = inputOf(building { Toggle("X", isOn: unused, .attr("name", "darkmode"), .class("mine")) })!
        #expect(input.attributes["name"] == "darkmode")
        #expect(input.attributes["class"] == "mine")
    }

    @Test("Field convenience renders the error when touched + invalid") func fieldConvenienceError() {
        var value = false
        var ctrl = FormController()
        ctrl.touched.insert("on")
        let vb = Binding<Bool>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("on", vb, cb, .custom("Required") { $0 })   // valid only when true
        let node = building { Toggle("X", field: field) }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
    }

    @Test("Field convenience wires blur to markTouched") func fieldConvenienceBlur() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = false
        var ctrl = FormController()
        let vb = Binding<Bool>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("on", vb, cb, .custom("Required") { $0 })
        let input = inputOf(Toggle("X", field: field))!
        #expect(ctrl.touched.contains("on") == false)
        registry.dispatch(id: input.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("on"))
    }

    @Test("the input is the immediate previous sibling of the track (adjacency the CSS needs)") func inputPrecedesTrack() {
        let row = rowOf(building { Toggle("X", isOn: unused) })!
        let kids = row.children.compactMap { el($0) }
        let i = kids.firstIndex { $0.tag == "input" }!
        #expect(kids[i + 1].attributes["class"] == "sw-switch__track")   // `:checked + .track` depends on this
    }

    @Test("switch stylesheet is token-driven: track + thumb, accent when on, visible focus") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-switch__track"))
        #expect(css.contains(".sw-switch__thumb"))
        #expect(css.contains("input:checked + .sw-switch__track"))            // accent when on
        #expect(css.contains("input:focus-visible + .sw-switch__track"))      // focus ring moved to the track
        #expect(css.contains("var(--sw-accent)"))
        #expect(css.contains("var(--sw-duration)"))                           // slide honors reduced-motion
    }
}
