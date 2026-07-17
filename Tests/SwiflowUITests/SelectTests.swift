// Tests/SwiflowUITests/SelectTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .selection / .on(.blur) paths
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

// root div -> label (child 0) -> the <select> among the label's children.
@MainActor private func selectOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "select" }
}

@MainActor private func optionsOf(_ root: VNode) -> [ElementData] {
    guard let sel = selectOf(root) else { return [] }
    return sel.children.compactMap { el($0) }.filter { $0.tag == "option" }
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

@Suite("Select")
@MainActor
struct SelectTests {
    private let unused = Binding<String>(get: { "" }, set: { _ in })

    @Test("renders a select in the field chrome with one option per choice") func rendersChrome() {
        let node = building { Select("Color", selection: unused, options: ["Red", "Green", "Blue"]) }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let sel = selectOf(node)!
        #expect(sel.tag == "select")
        #expect(sel.attributes["aria-invalid"] == "false")
        #expect(allText(node).contains("Color"))
        let opts = optionsOf(node)
        #expect(opts.count == 3)
    }

    @Test("string-literal options set value == label; explicit options keep them distinct") func optionValuesAndLabels() {
        let opts = optionsOf(building { Select("X", selection: unused, options: ["Red", SelectOption("g", "Green")]) })
        #expect(opts[0].attributes["value"] == "Red")
        #expect(allText(.element(opts[0])) == "Red")
        #expect(opts[1].attributes["value"] == "g")
        #expect(allText(.element(opts[1])) == "Green")
    }

    @Test("a placeholder prepends an empty-value first option") func placeholderOption() {
        let opts = optionsOf(building { Select("X", selection: unused, options: ["Red"], placeholder: "Choose…") })
        #expect(opts.count == 2)
        #expect(opts[0].attributes["value"] == "")
        #expect(allText(.element(opts[0])) == "Choose…")
    }

    @Test("the option matching the bound value is marked selected (mount-order fix)") func selectedOptionMarked() {
        // A non-first initial/persisted value must render selected — the bound value
        // property lands before the options exist, so `selected` is what shows it at mount.
        let binding = Binding<String>(get: { "2.5" }, set: { _ in })
        let opts = optionsOf(building {
            Select("Magnitude", selection: binding,
                   options: [SelectOption("all", "All"), SelectOption("1.0", "M1.0+"), SelectOption("2.5", "M2.5+")])
        })
        #expect(opts[0].attributes["selected"] == nil)   // "all" not selected
        #expect(opts[2].attributes["selected"] == "")    // "2.5" (3rd option) selected
    }

    @Test("with a placeholder and an empty binding, the placeholder option is selected") func placeholderSelectedWhenEmpty() {
        let opts = optionsOf(building { Select("X", selection: unused, options: ["Red"], placeholder: "Choose…") })
        #expect(opts[0].attributes["selected"] == "")    // empty-value placeholder matches the "" binding
        #expect(opts[1].attributes["selected"] == nil)
    }

    @Test("the selection binding reflects on render and writes back on change") func selectionRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var stored = "Red"
        let binding = Binding<String>(get: { stored }, set: { stored = $0 })
        let sel = selectOf(Select("X", selection: binding, options: ["Red", "Green"]))!
        if case .string(let v)? = sel.properties["value"] { #expect(v == "Red") }
        else { Issue.record("value property not a string") }
        registry.dispatch(id: sel.handlers["change"]!.id, event: EventInfo(type: "change", targetValue: "Green"))
        #expect(stored == "Green")
    }

    @Test("an error sets aria-invalid and renders a role=alert message") func errorChrome() {
        let node = building { Select("Role", selection: unused, options: ["Member"], error: "Pick one") }
        #expect(selectOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node)!.attributes["role"] == "alert")
        #expect(allText(node).contains("Pick one"))
    }

    @Test("disabled and required lower to the expected attributes") func disabledAndRequired() {
        let sel = selectOf(building { Select("X", selection: unused, options: ["A"], required: true, disabled: true) })!
        #expect(sel.attributes["disabled"] == "")
        #expect(sel.attributes["aria-required"] == "true")
    }

    @Test("layout: .horizontal adds the sw-field--h root modifier") func layoutHorizontal() {
        let root = el(building { Select("X", selection: unused, options: ["A"], layout: .horizontal) })!
        #expect(root.attributes["class"]?.contains("sw-field--h") == true)
    }

    @Test("caller attributes and class land on the select") func callerAttributesOnSelect() {
        let sel = selectOf(building { Select("X", selection: unused, options: ["A"], .attr("name", "role"), .class("mine")) })!
        #expect(sel.attributes["name"] == "role")
        #expect(sel.attributes["class"] == "mine")
    }

    @Test("Field convenience renders the error when touched + invalid, and wires blur") func fieldConvenience() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var value = ""
        var ctrl = FormController()
        ctrl.touched.insert("role")
        let vb = Binding<String>(get: { value }, set: { value = $0 })
        let cb = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
        let field = Field("role", vb, cb, .required())
        let node = Select("Role", field: field, options: ["Member"])
        #expect(selectOf(node)!.attributes["aria-invalid"] == "true")
        #expect(errorOf(node) != nil)
        registry.dispatch(id: selectOf(node)!.handlers["blur"]!.id, event: EventInfo(type: "blur"))
        #expect(ctrl.touched.contains("role"))
    }

    @Test("stylesheet skins the select with Customizable Select CSS + a fallback") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains("appearance: none"))                 // fallback path
        #expect(css.contains("@supports (appearance: base-select)"))
        #expect(css.contains("appearance: base-select"))
        #expect(css.contains("::picker(select)"))
        #expect(css.contains("::picker-icon"))
        #expect(css.contains("option::checkmark"))
        // Chevron unification: the modern picker-icon masks the shared chevron and fills
        // it with the muted token (same as the Dropdown caret); the fallback bakes the
        // muted color into the SVG and swaps light/dark, so both branches are dark-adaptive.
        #expect(css.contains("background-color: var(--sw-text-muted)"))   // masked, token-colored
        #expect(css.contains("mask: url("))                               // not content:url (which bakes black)
        #expect(css.contains("background-image: light-dark("))            // fallback adapts to scheme
        // Chrome's base-select UA styles make the <select> a flex container with
        // align-items: normal, which pins the fixed-height icon to the cross-axis
        // start (visually above the text's center) — the icon must self-center.
        #expect(css.contains("align-self: center"))
        // Picker open/close animation: the shared top-layer quartet (drop 10px + fade),
        // keyed on select:open so it reverses on close; @starting-style drives entry.
        #expect(css.contains("select:open::picker(select)"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("translateY(-10px)"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
