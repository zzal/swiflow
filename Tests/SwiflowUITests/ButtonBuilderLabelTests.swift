// Tests/SwiflowUITests/ButtonBuilderLabelTests.swift
//
// Audit V Wave-2 #7 (the wave's final item): the @ChildrenBuilder label
// overload whose unlabeled trailing-closure slot Button's doc RESERVED in
// M4 (`action:` was made a labeled closure precisely for this). Plus the
// user-selected a11y guardrail: an icon-only button with no aria-label has
// no accessible name — DEBUG warns.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@MainActor
private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@MainActor
private func captureWarnings(_ body: () -> Void) -> [String] {
    var captured: [String] = []
    let prior = _swiflowWarnOverride
    _swiflowWarnOverride = { captured.append($0) }
    defer { _swiflowWarnOverride = prior }
    body()
    return captured
}

/// A stand-in icon: a masked span with no text content (the house pattern).
@MainActor private func fakeIcon() -> VNode {
    element("span", attributes: [.class("sw-test-icon"), .attr("aria-hidden", "true")], children: [])
}

@Suite("Button builder label")
@MainActor
struct ButtonBuilderLabelTests {

    @Test("builder children render in order inside the <button>; skin classes intact")
    func childrenRenderInOrder() {
        let b = elementOf(building {
            Button(variant: .danger, action: {}) { fakeIcon(); text("Delete") }
        })!
        #expect(b.tag == "button")
        #expect(b.attributes["class"] == "sw-btn sw-btn--danger sw-btn--md")
        #expect(b.children.count == 2)
        if case .element(let icon) = b.children[0] { #expect(icon.attributes["class"] == "sw-test-icon") }
        else { Issue.record("first child should be the icon") }
        if case .text(let t) = b.children[1] { #expect(t == "Delete") }
        else { Issue.record("second child should be the text") }
    }

    @Test("the builder overload's action dispatches")
    func actionDispatches() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var fired = false
        let b = elementOf(Button(action: { fired = true }) { text("Go") })!
        registry.dispatch(id: b.handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("the form-button builder twin renders type=submit with no click handler")
    func submitBuilderTwin() {
        let b = elementOf(building { Button(type: .submit) { fakeIcon(); text("Save") } })!
        #expect(b.attributes["type"] == "submit")
        #expect(b.handlers["click"] == nil)
    }

    @Test("GUARD: icon-only with no aria-label warns once, naming the fix")
    func iconOnlyWarns() {
        let warnings = captureWarnings {
            _ = building { Button(action: {}) { fakeIcon() } }
        }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("aria-label"))
        #expect((warnings.first ?? "").contains("accessible name"))
    }

    @Test("GUARD: aria-label silences the icon-only warn")
    func ariaLabelSilences() {
        let warnings = captureWarnings {
            _ = building { Button(.attr("aria-label", "Delete"), action: {}) { fakeIcon() } }
        }
        #expect(warnings.isEmpty)
    }

    @Test("GUARD: text content anywhere in the label silences")
    func textSilences() {
        let warnings = captureWarnings {
            _ = building { Button(action: {}) { fakeIcon(); text("Delete") } }
        }
        #expect(warnings.isEmpty)
    }

    @Test("string-titled buttons never trip the guard")
    func stringTitleSilent() {
        let warnings = captureWarnings {
            _ = building { Button("Save") {} }
        }
        #expect(warnings.isEmpty)
    }
}
