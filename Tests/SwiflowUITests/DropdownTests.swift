// Tests/SwiflowUITests/DropdownTests.swift
// Dropdown is a Popover-API menu: a trigger button + an anchored popover of items,
// each closing the menu on select via popovertargetaction="hide". It's a @Component
// (behind the Dropdown free fn) so the popover id is stable across re-renders. These
// host tests cover structure + the id/anchor/close wiring; open/close + anchoring are
// native (Popover API + CSS anchor positioning), browser-verified on the demo.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func firstWithClass(_ root: ElementData, _ cls: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
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

// The DropdownMenu @Component body (what the Dropdown free fn embeds).
@MainActor private func dd(
    _ label: String = "Actions",
    placement: DropdownPlacement = .bottomStart,
    items: @escaping () -> [VNode]
) -> VNode {
    DropdownMenu(label: label, placement: placement, triggerAttrs: [], items: items).body
}

@Suite("Dropdown")
@MainActor
struct DropdownTests {
    @Test("renders a trigger + an anchored popover menu wired by a shared id") func renders() {
        let node = building { dd { [DropdownItem("Edit") {}, DropdownItem("Delete", variant: .danger) {}] } }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-dropdown")
        let trigger = firstWithClass(root, "sw-dropdown__trigger")!
        let menu = firstWithClass(root, "sw-dropdown__menu")!
        #expect(trigger.tag == "button")
        #expect(trigger.attributes["type"] == "button")
        #expect(trigger.attributes["aria-haspopup"] == "true")
        #expect(menu.attributes["popover"] == "auto")
        let menuID = menu.attributes["id"]!
        #expect(trigger.attributes["popovertarget"] == menuID)
        #expect(trigger.style["anchor-name"] == "--\(menuID)")
        #expect(menu.style["position-anchor"] == "--\(menuID)")
        #expect(allText(node).contains("Actions"))
    }

    @Test("the popover id is stable across re-renders (the reason it's a @Component)") func stableID() {
        let menu = DropdownMenu(label: "A", placement: .bottomStart, triggerAttrs: [], items: { [] })
        let id1 = building { firstWithClass(el(menu.body)!, "sw-dropdown__menu")!.attributes["id"]! }
        let id2 = building { firstWithClass(el(menu.body)!, "sw-dropdown__menu")!.attributes["id"]! }
        #expect(id1 == id2)   // same instance → same id across body() calls
    }

    @Test("each item closes the menu on select (popovertarget + hide) and carries its action") func itemWiring() {
        let node = building { dd { [DropdownItem("Edit") {}] } }
        let menuID = firstWithClass(el(node)!, "sw-dropdown__menu")!.attributes["id"]!
        let item = firstWithClass(el(node)!, "sw-dropdown__item")!
        #expect(item.tag == "button")
        #expect(item.attributes["popovertarget"] == menuID)
        #expect(item.attributes["popovertargetaction"] == "hide")
        #expect(item.handlers["click"] != nil)
    }

    @Test("clicking an item runs its action") func itemAction() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var clicked = false
        let node = dd { [DropdownItem("Edit") { clicked = true }] }
        let item = firstWithClass(el(node)!, "sw-dropdown__item")!
        registry.dispatch(id: item.handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(clicked)
    }

    @Test("a disabled item has no action and no close wiring") func disabledItem() {
        let item = firstWithClass(el(building { dd { [DropdownItem("X", disabled: true) {}] } })!, "sw-dropdown__item")!
        #expect(item.attributes["disabled"] == "")
        #expect(item.handlers["click"] == nil)
        #expect(item.attributes["popovertarget"] == nil)
    }

    @Test("danger variant maps to the modifier class") func dangerVariant() {
        #expect(firstWithClass(el(building { dd { [DropdownItem("Del", variant: .danger) {}] } })!, "sw-dropdown__item--danger") != nil)
    }

    @Test("DropdownDivider renders a role=separator") func divider() {
        let node = building { dd { [DropdownItem("X") {}, DropdownDivider()] } }
        #expect(firstWithClass(el(node)!, "sw-dropdown__divider")!.attributes["role"] == "separator")
    }

    @Test("placement sets the menu's position-area") func placement() {
        let menu = firstWithClass(el(building { dd(placement: .bottomEnd) { [DropdownItem("X") {}] } })!, "sw-dropdown__menu")!
        #expect(menu.style["position-area"] == "bottom span-left")
    }

    @Test("a DropdownItem outside a Dropdown degrades — action wired, no close target") func itemOutsideDropdown() {
        let item = el(building { DropdownItem("Edit") {} })!
        #expect(item.handlers["click"] != nil)
        #expect(item.attributes["popovertarget"] == nil)   // no ambient menu id → no close wiring
    }

    @Test("the public Dropdown(...) free function lowers to an embedded component") func freeFunctionEmbeds() {
        let node = building { Dropdown("Actions") { DropdownItem("Edit") {} } }
        if case .component = node {} else { Issue.record("expected an embedded component node, got \(node)") }
    }

    @Test("stylesheet: anchored popover menu with token-driven entry animation") func stylesheet() {
        let css = dropdownStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-dropdown__menu"))
        #expect(css.contains(":popover-open"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("var(--sw-duration)"))          // → reduced-motion collapses the animation
        #expect(css.contains(".sw-dropdown__item--danger"))
        #expect(css.contains("var(--sw-surface)"))
    }
}
