// Tests/SwiflowUITests/ButtonTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the click-handler path
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

// An enabled Button calls `.on(.click)`, which precondition-requires an ambient
// handler registry (normally set during render). Provide one for construction.
@MainActor
private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("Button")
@MainActor
struct ButtonTests {
    @Test("Button renders <button type=button> with the title and default skin classes") func rendersButton() {
        let b = elementOf(building { Button("Save") {} })!
        #expect(b.tag == "button")
        #expect(b.attributes["type"] == "button")
        #expect(b.attributes["class"] == "sw-btn sw-btn--primary sw-btn--md")
        #expect(b.children.count == 1)
        if case .text(let t) = b.children[0] { #expect(t == "Save") } else { Issue.record("no text child") }
    }

    @Test("variant and size map to modifier classes") func variantAndSizeClasses() {
        let b = elementOf(building { Button("X", variant: .ghost, size: .lg) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--ghost sw-btn--lg")
    }

    @Test("the compact .xs size maps to sw-btn--xs and the sheet styles it") func xsSize() {
        let b = elementOf(building { Button("X", size: .xs) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--primary sw-btn--xs")
        #expect(buttonStyleSheet.cssString(scopeClass: "").contains(".sw-btn--xs"))
    }

    @Test(".danger is a destructive solid fill on the danger token family") func dangerVariant() {
        let b = elementOf(building { Button("Delete", variant: .danger) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--danger sw-btn--md")
        let css = buttonStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-btn--danger"))
        #expect(css.contains("var(--sw-danger-text)"), "solid fill needs the paired text token — never raw white")
        #expect(css.contains("var(--sw-danger-hover)") && css.contains("var(--sw-danger-active)"),
                "hover/active read dedicated tokens so they stay dark-mode-correct")
    }

    @Test("disabled emits the disabled attribute and attaches no click handler") func disabledNoHandler() {
        // No ambient needed: the disabled path never calls .on(.click).
        let b = elementOf(Button("X", disabled: true) {})!
        #expect(b.attributes["disabled"] == "")     // presence-only HTML boolean attribute
        #expect(b.handlers["click"] == nil)
    }

    @Test("enabled button attaches a click handler") func enabledHasHandler() {
        let b = elementOf(building { Button("X") {} })!
        #expect(b.handlers["click"] != nil)
    }

    @Test("the click handler dispatches the action") func handlerDispatches() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var fired = false
        let b = elementOf(Button("X") { fired = true })!
        registry.dispatch(id: b.handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("caller class merges with the skin classes instead of clobbering them") func callerClassMerges() {
        let b = elementOf(building { Button("X", .class("mine")) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--primary sw-btn--md mine")
    }

    @Test("caller attribute can override the default type (applied last)") func callerOverridesType() {
        let b = elementOf(building { Button("Go", .attr("type", "submit")) {} })!
        #expect(b.attributes["type"] == "submit")
    }

    @Test("multiple caller classes all merge; an empty class adds no stray separator") func mergesMultipleAndEmptyClasses() {
        let b = elementOf(building { Button("X", .class("a"), .class(""), .class("b")) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--primary sw-btn--md a b")
    }

    @Test("a class nested in a .compound is merged, not flattened last over the skin") func mergesCompoundClass() {
        let b = elementOf(building { Button("X", .compound([.class("nested"), .id("go")])) {} })!
        #expect(b.attributes["class"] == "sw-btn sw-btn--primary sw-btn--md nested")
        #expect(b.attributes["id"] == "go")   // the compound's non-class part still applies
    }

    @Test("button stylesheet reads tokens and defines interaction states") func stylesheetIsTokenDriven() {
        let css = buttonStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-btn"))
        #expect(css.contains("var(--sw-accent)"))
        #expect(css.contains("var(--sw-accent-hover)"))  // hover reads a token, not in-component color-mix
        #expect(css.contains("var(--sw-duration)"))      // transition honors reduced-motion
        #expect(css.contains("var(--sw-focus-ring)"))    // focus ring honors prefers-contrast
        #expect(css.contains("var(--sw-disabled-opacity)"))
        #expect(css.contains(":focus-visible"))
        #expect(css.contains(":disabled"))
        #expect(css.contains(":hover:not(:disabled)"))
        #expect(css.contains(":active:not(:disabled)"))  // press feedback (touch has no hover)
        #expect(css.contains(".sw-btn--primary"))
        #expect(css.contains(".sw-btn--ghost"))
    }

    @Test("button stylesheet has balanced braces (guards the hand-authored raw block)") func bracesBalanced() {
        let css = buttonStyleSheet.cssString(scopeClass: "")
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
