// Tests/SwiflowUITests/NumberFieldTests.swift
import Testing
@testable import Swiflow   // HandlerAmbient / HandlerRegistry for the .value path
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

// root div -> label (child 0) -> the <input> among the label's children.
@MainActor private func inputOf(_ root: VNode) -> ElementData? {
    guard let r = el(root), let labelEl = el(r.children.first) else { return nil }
    return labelEl.children.lazy.compactMap { el($0) }.first { $0.tag == "input" }
}

// root div -> the error <p> sibling, if present.
@MainActor private func errorOf(_ root: VNode) -> ElementData? {
    guard let r = el(root) else { return nil }
    return r.children.lazy.compactMap { el($0) }.first { $0.tag == "p" }
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):            return s
    case .element(let d):         return d.children.map(allText).joined()
    case .fragment(let xs):       return xs.map(allText).joined()
    case .environmentOverride(_, let child): return allText(child)
    default:                      return ""
    }
}

// .value / .on(.blur) register through the ambient handler registry (set during
// render); provide one for direct construction.
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("NumberField")
@MainActor
struct NumberFieldTests {
    private let unusedDouble = Binding<Double>(get: { 0 }, set: { _ in })
    private let unusedInt = Binding<Int>(get: { 0 }, set: { _ in })

    @Test("renders a labelled native number input with field chrome and no error by default") func rendersFieldChromeWithNumberInput() {
        let node = building { NumberField("Quantity", value: unusedDouble) }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let input = inputOf(node)
        #expect(input != nil)
        #expect(input?.tag == "input")
        #expect(input?.attributes["type"] == "number")
        #expect(allText(node).contains("Quantity"))
        #expect(errorOf(node) == nil)
    }

    @Test("min/max/step are omitted when nil") func minMaxStepOmittedWhenNil() {
        let input = inputOf(building { NumberField("Quantity", value: unusedDouble) })!
        #expect(input.attributes["min"] == nil)
        #expect(input.attributes["max"] == nil)
        #expect(input.attributes["step"] == nil)
    }

    @Test("min/max/step lower to formatted attributes, trimming a trailing .0") func minMaxStepFormatted() {
        let input = inputOf(building { NumberField("Quantity", value: unusedDouble, min: 0, max: 10, step: 0.5) })!
        #expect(input.attributes["min"] == "0")
        #expect(input.attributes["max"] == "10")
        #expect(input.attributes["step"] == "0.5")
    }

    @Test("a negative whole number formats without a trailing .0") func negativeWholeNumberFormatted() {
        let input = inputOf(building { NumberField("Delta", value: unusedDouble, min: -5) })!
        #expect(input.attributes["min"] == "-5")
    }

    @Test("a fractional value stays fractional") func fractionalValueStaysFractional() {
        let input = inputOf(building { NumberField("Quantity", value: unusedDouble, step: 0.25) })!
        #expect(input.attributes["step"] == "0.25")
    }

    @Test("Int overload compiles and emits integer min/max/step strings") func intOverloadEmitsIntegerStrings() {
        let input = inputOf(building { NumberField("Age", value: unusedInt, min: 0, max: 120, step: 1) })!
        #expect(input.attributes["type"] == "number")
        #expect(input.attributes["min"] == "0")
        #expect(input.attributes["max"] == "120")
        #expect(input.attributes["step"] == "1")
    }

    @Test("an error renders a role=alert message and sets aria-invalid on the input") func errorRendersAlertAndAriaInvalid() {
        let node = building { NumberField("Quantity", value: unusedDouble, error: "Required") }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
        let err = errorOf(node)!
        #expect(err.attributes["role"] == "alert")
        #expect(allText(.element(err)) == "Required")

        let clean = building { NumberField("Quantity", value: unusedDouble) }
        #expect(inputOf(clean)!.attributes["aria-invalid"] == "false")
        #expect(errorOf(clean) == nil)
    }

    @Test("disabled sets the disabled attribute on the input") func disabledSetsAttribute() {
        let input = inputOf(building { NumberField("Quantity", value: unusedDouble, disabled: true) })!
        #expect(input.attributes["disabled"] == "")   // presence-only boolean attr
    }

    @Test("size sets the field modifier class") func sizeModifier() {
        let root = el(building { NumberField("Quantity", value: unusedDouble, size: .lg) })!
        #expect(root.attributes["class"] == "sw-field sw-field--lg")
    }

    @Test("caller attributes land on the input and apply last") func callerAttributesLandOnInput() {
        let input = inputOf(building { NumberField("Quantity", value: unusedDouble, .attr("name", "qty")) })!
        #expect(input.attributes["name"] == "qty")
    }

    @Test("the Double value binding reflects on render and writes back on input") func doubleValueBindingRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var stored = 1.5
        let binding = Binding<Double>(get: { stored }, set: { stored = $0 })
        let input = inputOf(NumberField("Quantity", value: binding))!
        if case .string(let v)? = input.properties["value"] { #expect(v == "1.5") }
        else { Issue.record("value property not a string") }
        registry.dispatch(id: input.handlers["input"]!.id, event: EventInfo(type: "input", targetValue: "2.5"))
        #expect(stored == 2.5)
    }

    @Test("the Int value binding reflects on render and writes back on input") func intValueBindingRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var stored = 3
        let binding = Binding<Int>(get: { stored }, set: { stored = $0 })
        let input = inputOf(NumberField("Age", value: binding))!
        if case .string(let v)? = input.properties["value"] { #expect(v == "3") }
        else { Issue.record("value property not a string") }
        registry.dispatch(id: input.handlers["input"]!.id, event: EventInfo(type: "input", targetValue: "42"))
        #expect(stored == 42)
    }
}
