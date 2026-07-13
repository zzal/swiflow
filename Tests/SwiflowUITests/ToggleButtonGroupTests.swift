// Tests/SwiflowUITests/ToggleButtonGroupTests.swift
// ToggleButtonGroup is a stateless, String-keyed segmented control (id == label, like
// RadioGroup/Select) shared by two overloads — single-select Binding<String> (one
// pressed) and multi-select Binding<Set<String>> (toggle membership) — through one
// private lowering. No roving focus: buttons are independently tabbable (see
// ToggleButtonGroup.swift's doc comment for the RadioGroup/Tabs alternative). These
// host tests mirror TabsTests/RadioGroupTests: structure + aria-pressed state, then
// click dispatched through HandlerRegistry (the `building { }` seam).
import Testing
@testable import Swiflow      // HandlerAmbient / HandlerRegistry / EventInfo for the click dispatch
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func buttons(_ root: ElementData) -> [ElementData] {
    root.children.compactMap { el($0) }
}

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("ToggleButtonGroup")
@MainActor
struct ToggleButtonGroupTests {
    // MARK: - Single-select (Binding<String>)

    @Test("renders a role=group div of one button per option") func rendersGroup() {
        let selection = Binding<String>(get: { "left" }, set: { _ in })
        let root = el(building { ToggleButtonGroup(selection: selection, options: ["left", "center", "right"]) })!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-togglegroup")
        #expect(root.attributes["role"] == "group")
        let btns = buttons(root)
        #expect(btns.count == 3)
        #expect(btns.allSatisfy { $0.tag == "button" })
        #expect(btns.allSatisfy { $0.attributes["type"] == "button" })
        #expect(btns.allSatisfy { $0.attributes["class"] == "sw-togglegroup__btn" })
    }

    @Test("exactly the selected option's button is aria-pressed=true, the rest false") func exactlyOnePressed() {
        let selection = Binding<String>(get: { "center" }, set: { _ in })
        let btns = buttons(el(building { ToggleButtonGroup(selection: selection, options: ["left", "center", "right"]) })!)
        #expect(btns[0].attributes["aria-pressed"] == "false")
        #expect(btns[1].attributes["aria-pressed"] == "true")
        #expect(btns[2].attributes["aria-pressed"] == "false")
    }

    @Test("clicking a button dispatches through HandlerRegistry and sets selection to that option") func clickSetsSelection() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var chosen = "left"
        let selection = Binding<String>(get: { chosen }, set: { chosen = $0 })
        let btns = buttons(el(ToggleButtonGroup(selection: selection, options: ["left", "center", "right"]))!)
        registry.dispatch(id: btns[2].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(chosen == "right")
    }

    // MARK: - Multi-select (Binding<Set<String>>)

    @Test("multi: buttons for members of the set are aria-pressed=true") func multiMembersPressed() {
        let selection = Binding<Set<String>>(get: { ["bold", "italic"] }, set: { _ in })
        let btns = buttons(el(building { ToggleButtonGroup(selection: selection, options: ["bold", "italic", "underline"]) })!)
        #expect(btns[0].attributes["aria-pressed"] == "true")
        #expect(btns[1].attributes["aria-pressed"] == "true")
        #expect(btns[2].attributes["aria-pressed"] == "false")
    }

    @Test("multi: clicking a pressed button removes it from the set") func clickRemoves() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var members: Set<String> = ["bold", "italic"]
        let selection = Binding<Set<String>>(get: { members }, set: { members = $0 })
        let btns = buttons(el(ToggleButtonGroup(selection: selection, options: ["bold", "italic", "underline"]))!)
        registry.dispatch(id: btns[0].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(members == ["italic"])
    }

    @Test("multi: clicking an unpressed button adds it to the set") func clickAdds() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var members: Set<String> = ["bold"]
        let selection = Binding<Set<String>>(get: { members }, set: { members = $0 })
        let btns = buttons(el(ToggleButtonGroup(selection: selection, options: ["bold", "italic", "underline"]))!)
        registry.dispatch(id: btns[1].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(members == ["bold", "italic"])
    }

    // MARK: - Caller attrs, shared across both overloads

    @Test("caller attrs/.class merge onto the group div") func callerAttrsMerge() {
        let selection = Binding<String>(get: { "left" }, set: { _ in })
        let root = el(building {
            ToggleButtonGroup(selection: selection, options: ["left"], .class("mine"), .data("test", "tbg"))
        })!
        #expect(root.attributes["class"] == "sw-togglegroup mine")
        #expect(root.attributes["data-test"] == "tbg")
    }

    @Test("stylesheet: segmented look, token-driven, keyed off aria-pressed") func stylesheet() {
        let css = toggleButtonGroupStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-togglegroup"))
        #expect(css.contains(".sw-togglegroup__btn"))
        #expect(css.contains("aria-pressed"))
        #expect(css.contains("var(--sw-accent)"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
