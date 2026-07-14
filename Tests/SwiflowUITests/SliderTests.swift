// Tests/SwiflowUITests/SliderTests.swift
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

@Suite("Slider")
@MainActor
struct SliderTests {
    private let unused = Binding<Double>(get: { 0 }, set: { _ in })

    @Test("renders a labelled native range input with field chrome and no error by default") func rendersFieldChromeWithRangeInput() {
        let node = building { Slider("Volume", value: unused) }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-field sw-field--md")
        let input = inputOf(node)
        #expect(input != nil)
        #expect(input?.tag == "input")
        #expect(input?.attributes["type"] == "range")
        #expect(allText(node).contains("Volume"))
        #expect(errorOf(node) == nil)
    }

    @Test("min/max default to 0/1, formatted like NumberField") func defaultRangeFormatted() {
        let input = inputOf(building { Slider("Volume", value: unused) })!
        #expect(input.attributes["min"] == "0")
        #expect(input.attributes["max"] == "1")
    }

    @Test("min/max reflect the given range, formatted (trimming a trailing .0)") func customRangeFormatted() {
        let input = inputOf(building { Slider("Volume", value: unused, in: 0...10) })!
        #expect(input.attributes["min"] == "0")
        #expect(input.attributes["max"] == "10")
    }

    @Test("step is omitted when nil") func stepOmittedWhenNil() {
        let input = inputOf(building { Slider("Volume", value: unused) })!
        #expect(input.attributes["step"] == nil)
    }

    @Test("the drawn track's fill var reflects the value's position in the range, clamped") func fillVarTracksValue() {
        let at25 = Binding<Double>(get: { 2.5 }, set: { _ in })
        let input = inputOf(building { Slider("Volume", value: at25, in: 0...10) })!
        #expect(input.style["--sw-slider-fill"] == "25%")
        // Clamped: a bound value outside the range must not paint outside the track.
        let over = Binding<Double>(get: { 42 }, set: { _ in })
        #expect(inputOf(building { Slider("Volume", value: over, in: 0...10) })!.style["--sw-slider-fill"] == "100%")
        let under = Binding<Double>(get: { -1 }, set: { _ in })
        #expect(inputOf(building { Slider("Volume", value: under, in: 0...10) })!.style["--sw-slider-fill"] == "0%")
    }

    @Test("stylesheet draws the range (not native accent-color): borderless track, surface-ringed thumb") func stylesheet() {
        let css = formControlsSheet.cssString(scopeClass: "")
        // Reshaped geometry: borderless pill track with a --sw-slider-fill accent
        // layer (webkit) / ::-moz-range-progress (gecko); 1.25em accent knob with a
        // real 2px stroke — white in light, black in dark (explicit light-dark, not
        // --sw-surface: dark surface is gray and reads as no stroke).
        #expect(css.contains("::-webkit-slider-runnable-track"))
        #expect(css.contains("::-moz-range-track"))
        #expect(css.contains("::-moz-range-progress"))
        #expect(css.contains("var(--sw-slider-fill, 0%)"))
        #expect(css.contains("::-webkit-slider-thumb"))
        #expect(css.contains("::-moz-range-thumb"))
        #expect(css.contains("border: 2px solid light-dark(#fff, #000)"))
        #expect(!css.contains("accent-color:"))   // fully drawn — no native tinting left
    }

    @Test("step lowers to a formatted attribute when given") func stepFormatted() {
        let input = inputOf(building { Slider("Volume", value: unused, in: 0...10, step: 1) })!
        #expect(input.attributes["step"] == "1")
    }

    @Test("the value binding reflects on render and writes back on input") func valueBindingRoundTrips() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var stored = 0.5
        let binding = Binding<Double>(get: { stored }, set: { stored = $0 })
        let input = inputOf(Slider("Volume", value: binding))!
        if case .string(let v)? = input.properties["value"] { #expect(v == "0.5") }
        else { Issue.record("value property not a string") }
        registry.dispatch(id: input.handlers["input"]!.id, event: EventInfo(type: "input", targetValue: "0.75"))
        #expect(stored == 0.75)
    }

    @Test("an error renders a role=alert message and sets aria-invalid on the input") func errorRendersAlertAndAriaInvalid() {
        let node = building { Slider("Volume", value: unused, error: "Required") }
        #expect(inputOf(node)!.attributes["aria-invalid"] == "true")
        let err = errorOf(node)!
        #expect(err.attributes["role"] == "alert")
        #expect(allText(.element(err)) == "Required")

        let clean = building { Slider("Volume", value: unused) }
        #expect(inputOf(clean)!.attributes["aria-invalid"] == "false")
        #expect(errorOf(clean) == nil)
    }

    @Test("disabled sets the disabled attribute on the input") func disabledSetsAttribute() {
        let input = inputOf(building { Slider("Volume", value: unused, disabled: true) })!
        #expect(input.attributes["disabled"] == "")   // presence-only boolean attr
    }

    @Test("size sets the field modifier class") func sizeModifier() {
        let root = el(building { Slider("Volume", value: unused, size: .lg) })!
        #expect(root.attributes["class"] == "sw-field sw-field--lg")
    }

    @Test("caller attributes land on the input and apply last") func callerAttributesLandOnInput() {
        let input = inputOf(building { Slider("Volume", value: unused, .attr("name", "vol")) })!
        #expect(input.attributes["name"] == "vol")
    }
}
