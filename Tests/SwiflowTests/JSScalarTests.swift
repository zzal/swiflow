// Tests/SwiflowTests/JSScalarTests.swift
//
// The host-testable core of the Swift↔JS scalar crossing. Before this existed,
// the classification rules (Bool-before-Int, HMRNilSentinel↔null, integral
// numbers) were re-derived inside the JavaScriptKit-only encode/decode paths,
// which no unit test could reach — the exact gap that let the "Blocker 2/3" HMR
// coercion bugs ship. These pin the Swift-side rules; the thin `JSValue`
// crossing (`init?(jsValue:)`/`jsValue`) stays wasm-only.

import Testing
@testable import Swiflow

@Suite("JSScalar — host-testable Any↔scalar coercion")
struct JSScalarTests {

    @Test("Bool is classified BEFORE Int (Bool bridges to NSNumber)")
    func boolBeforeInt() {
        // The regression guard: a naive `as? Int`-first would turn `true` into
        // `.int(1)`, corrupting a `@State var flag: Bool` across an HMR reload.
        #expect(JSScalar(stateValue: true) == .bool(true))
        #expect(JSScalar(stateValue: false) == .bool(false))
    }

    @Test("String / Int / Double classify to their matching case")
    func primitives() {
        #expect(JSScalar(stateValue: "hi") == .string("hi"))
        #expect(JSScalar(stateValue: 42) == .int(42))
        #expect(JSScalar(stateValue: 3.5) == .double(3.5))
    }

    @Test("HMRNilSentinel classifies as .null; .null restores to a sentinel")
    func nullSentinel() {
        #expect(JSScalar(stateValue: HMRNilSentinel()) == .null)
        #expect(JSScalar.null.stateValue is HMRNilSentinel)
    }

    @Test("unsupported types classify as nil (the encoder skips them)")
    func unsupportedIsNil() {
        #expect(JSScalar(stateValue: [1, 2, 3]) == nil)
        #expect(JSScalar(stateValue: ["k": "v"]) == nil)
    }

    @Test("stateValue round-trips the concrete primitives")
    func stateValueRoundTrip() {
        #expect(JSScalar.string("s").stateValue as? String == "s")
        #expect(JSScalar.int(7).stateValue as? Int == 7)
        #expect(JSScalar.double(1.5).stateValue as? Double == 1.5)
        #expect(JSScalar.bool(true).stateValue as? Bool == true)
    }

    @Test("PropertyValue maps to the matching scalar (no null in the property domain)")
    func propertyValueMapping() {
        #expect(PropertyValue.string("v").jsScalar == .string("v"))
        #expect(PropertyValue.int(3).jsScalar == .int(3))
        #expect(PropertyValue.double(2.0).jsScalar == .double(2.0))
        #expect(PropertyValue.bool(false).jsScalar == .bool(false))
    }
}
