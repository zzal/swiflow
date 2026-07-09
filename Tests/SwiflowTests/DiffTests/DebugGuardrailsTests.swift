// Tests/SwiflowTests/DiffTests/DebugGuardrailsTests.swift
//
// Part I Wave-3 DEBUG guardrails: the enriched mixed-keying message (names a
// keyed-component cause) and the silent <select> mount-order warn. Both are
// pure functions over the VNode tree, so they're tested directly.
import Testing
@testable import Swiflow

private final class Card: Component {
    var body: VNode { div {} }
}

@Suite("DEBUG guardrails")
@MainActor
struct DebugGuardrailsTests {

    // MARK: mixedKeyingDiagnostic

    @Test("consistent keying (all keyed / all unkeyed) → no diagnostic")
    func consistentKeyingIsQuiet() {
        let allKeyed: [VNode] = [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "li", key: "b")),
        ]
        let allUnkeyed: [VNode] = [.element(ElementData(tag: "li")), .element(ElementData(tag: "li"))]
        #expect(mixedKeyingDiagnostic(parentTag: "ul", children: allKeyed) == nil)
        #expect(mixedKeyingDiagnostic(parentTag: "ul", children: allUnkeyed) == nil)
    }

    @Test("mixed keying with only keyed ELEMENTS → generic message, no component sentence")
    func mixedElementsGivesGenericMessage() {
        let children: [VNode] = [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "li")),           // unkeyed
        ]
        let msg = mixedKeyingDiagnostic(parentTag: "ul", children: children)
        #expect(msg?.contains("mix keyed (1) and unkeyed (1)") == true)
        #expect(msg?.contains("keyed embedded component") == false)
    }

    @Test("mixed keying with a keyed COMPONENT → message names the component cause + container fix")
    func mixedKeyedComponentNamesCause() {
        let children: [VNode] = [
            .component(ComponentDescription(Card.self, key: "card-1", factory: { Card() })),
            .element(ElementData(tag: "h2")),           // unkeyed sibling
        ]
        let msg = mixedKeyingDiagnostic(parentTag: "div", children: children)
        #expect(msg?.contains("keyed embedded component needs keyed siblings") == true)
        #expect(msg?.contains("single-child container") == true)
    }

    // MARK: selectMountOrderDiagnostic

    private func select(bound: String, options: [(value: String, selected: Bool)]) -> ElementData {
        let optionNodes: [VNode] = options.map { opt in
            var attrs: [String: String] = ["value": opt.value]
            if opt.selected { attrs["selected"] = "" }
            return .element(ElementData(tag: "option", attributes: attrs, children: [.text(opt.value)]))
        }
        return ElementData(
            tag: "select",
            properties: ["value": .string(bound)],
            children: optionNodes
        )
    }

    @Test("bound value isn't the first option and no `selected` → warns with the fix")
    func warnsWhenBoundValueWontStick() {
        let data = select(bound: "B", options: [("A", false), ("B", false), ("C", false)])
        let msg = selectMountOrderDiagnostic(data)
        #expect(msg?.contains("won't show that value at first mount") == true)
        #expect(msg?.contains("'B'") == true)
        #expect(msg?.contains(".attr(\"selected\"") == true)
    }

    @Test("bound value IS the first option → quiet (browser default lands right)")
    func quietWhenBoundIsFirstOption() {
        let data = select(bound: "A", options: [("A", false), ("B", false)])
        #expect(selectMountOrderDiagnostic(data) == nil)
    }

    @Test("matching option carries `selected` → quiet (the workaround is applied)")
    func quietWhenMatchingOptionSelected() {
        let data = select(bound: "B", options: [("A", false), ("B", true), ("C", false)])
        #expect(selectMountOrderDiagnostic(data) == nil)
    }

    @Test("no option matches the bound value → quiet (a different problem, don't false-warn)")
    func quietWhenNoOptionMatches() {
        let data = select(bound: "Z", options: [("A", false), ("B", false)])
        #expect(selectMountOrderDiagnostic(data) == nil)
    }

    @Test("non-select element and empty bound value → quiet")
    func quietForNonSelectOrEmpty() {
        let notSelect = ElementData(tag: "div", properties: ["value": .string("B")],
                                    children: [.element(ElementData(tag: "option", attributes: ["value": "B"]))])
        #expect(selectMountOrderDiagnostic(notSelect) == nil)
        let empty = select(bound: "", options: [("A", false), ("B", false)])
        #expect(selectMountOrderDiagnostic(empty) == nil)
    }

    @Test("option value falls back to its text content when no value attribute")
    func optionValueFallsBackToText() {
        // Options with NO value attr — value is the text; bound "B" matches the
        // second option's text, which isn't first and has no `selected` → warns.
        let optionNodes: [VNode] = ["A", "B"].map {
            .element(ElementData(tag: "option", children: [.text($0)]))
        }
        let data = ElementData(tag: "select", properties: ["value": .string("B")], children: optionNodes)
        #expect(selectMountOrderDiagnostic(data)?.contains("'B'") == true)
    }
}
