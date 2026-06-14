// Tests/SwiflowUITests/RadioGroupTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .checked paths
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func radios(_ root: VNode) -> [ElementData] {
    guard let r = el(root) else { return [] }
    return r.children.compactMap { child -> ElementData? in
        guard let labelEl = el(child), labelEl.attributes["class"] == "sw-radio__option" else { return nil }
        return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
    }
}

@MainActor private func legendOf(_ root: VNode) -> ElementData? {
    guard let r = el(root) else { return nil }
    return r.children.lazy.compactMap { el($0) }.first { $0.tag == "legend" }
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

@Suite("RadioGroup")
@MainActor
struct RadioGroupTests {
    private let unused = Binding<String>(get: { "" }, set: { _ in })

    @Test("renders a fieldset/legend with one shared-name radio per option") func rendersFieldset() {
        let node = building { RadioGroup("Plan", selection: unused, options: ["Free", "Pro", "Team"]) }
        let root = el(node)!
        #expect(root.tag == "fieldset")
        #expect(root.attributes["class"] == "sw-radio")
        #expect(allText(.element(legendOf(node)!)) == "Plan")
        let rs = radios(node)
        #expect(rs.count == 3)
        #expect(rs.allSatisfy { $0.attributes["type"] == "radio" })
        // All radios share the same name → native single-selection + roving focus.
        #expect(Set(rs.compactMap { $0.attributes["name"] }) == ["plan"])   // slug of "Plan"
    }

    @Test("name slugs from the label, or takes an explicit override") func nameSlugAndOverride() {
        let slugged = radios(building { RadioGroup("Favorite Color", selection: unused, options: ["Red"]) })
        #expect(slugged.first?.attributes["name"] == "favorite-color")
        let explicit = radios(building { RadioGroup("Plan", selection: unused, options: ["A"], name: "billing") })
        #expect(explicit.first?.attributes["name"] == "billing")
    }

    @Test("checked reflects the selection; only the matching radio is checked") func checkedReflectsSelection() {
        let rs = building { radios(RadioGroup("X", selection: Binding(get: { "Pro" }, set: { _ in }), options: ["Free", "Pro"])) }
        if case .bool(let free)? = rs[0].properties["checked"] { #expect(free == false) }
        if case .bool(let pro)? = rs[1].properties["checked"] { #expect(pro == true) }
    }

    @Test("selecting a radio writes its value back to the binding") func selectingWritesBack() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var chosen = "Free"
        let binding = Binding<String>(get: { chosen }, set: { chosen = $0 })
        let rs = radios(RadioGroup("X", selection: binding, options: ["Free", "Pro"]))
        registry.dispatch(id: rs[1].handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: true))
        #expect(chosen == "Pro")
    }

    @Test("group error sets aria-invalid on the fieldset and renders a role=alert message") func errorChrome() {
        let node = building { RadioGroup("Plan", selection: unused, options: ["Free"], error: "Pick a plan") }
        #expect(el(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node)!.attributes["role"] == "alert")
        #expect(allText(node).contains("Pick a plan"))
    }

    @Test("required and disabled lower to fieldset-level attributes") func requiredAndDisabled() {
        let root = el(building { RadioGroup("X", selection: unused, options: ["A"], required: true, disabled: true) })!
        #expect(root.attributes["aria-required"] == "true")
        #expect(root.attributes["disabled"] == "")        // native <fieldset disabled> cascades
    }

    @Test("caller attributes and class land on the fieldset") func callerAttributesOnFieldset() {
        let root = el(building { RadioGroup("X", selection: unused, options: ["A"], .class("mine"), .data("test", "rg")) })!
        #expect(root.attributes["class"] == "sw-radio mine")   // merged, not clobbered
        #expect(root.attributes["data-test"] == "rg")
    }

    @Test("Field convenience shows the error when touched + invalid, and selecting marks touched") func fieldConvenience() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = ""
        var ctrl = FormController()
        ctrl.touched.insert("plan")
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("plan", vb, cb, .required())
        let node = RadioGroup("Plan", field: field, options: ["Free", "Pro"])
        #expect(el(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
        // Selecting marks touched via the per-option binding's setter (not a blur handler).
        var fresh = FormController()
        let cb2 = Binding<FormController>(get: { fresh }, set: { fresh = $0 })
        let field2 = Field("plan", vb, cb2, .required())
        let rs = radios(RadioGroup("Plan", field: field2, options: ["Free", "Pro"]))
        registry.dispatch(id: rs[0].handlers["change"]!.id, event: EventInfo(type: "change", targetChecked: true))
        #expect(fresh.touched.contains("plan"))
    }

    @Test("stylesheet skins the radio group, fieldset-reset and token-driven") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-radio"))
        #expect(css.contains(".sw-radio__legend"))
        #expect(css.contains("input[type=\"radio\"]"))
        #expect(css.contains("accent-color: var(--sw-accent)"))
        #expect(css.contains(".sw-radio[aria-invalid=\"true\"]"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
