// Tests/SwiflowTests/PropertyValueTests.swift
import Testing
@testable import Swiflow

@Suite("PropertyValue")
struct PropertyValueTests {
    @Test("Equality discriminates by case and value")
    func equalityByCaseAndValue() {
        #expect(PropertyValue.string("x") == PropertyValue.string("x"))
        #expect(PropertyValue.string("x") != PropertyValue.string("y"))
        #expect(PropertyValue.string("1") != PropertyValue.int(1))
        #expect(PropertyValue.int(1) == PropertyValue.int(1))
        #expect(PropertyValue.double(1.5) == PropertyValue.double(1.5))
        #expect(PropertyValue.bool(true) == PropertyValue.bool(true))
        #expect(PropertyValue.bool(true) != PropertyValue.bool(false))
    }

    @Test("PropertyValue accepts string/int/bool/double literals")
    func propertyValueLiterals() {
        let s: PropertyValue = "hi"
        let i: PropertyValue = 7
        let b: PropertyValue = true
        let d: PropertyValue = 1.5
        if case .string(let v) = s { #expect(v == "hi") } else { Issue.record("expected .string") }
        if case .int(let v) = i { #expect(v == 7) } else { Issue.record("expected .int") }
        if case .bool(let v) = b { #expect(v == true) } else { Issue.record("expected .bool") }
        if case .double(let v) = d { #expect(v == 1.5) } else { Issue.record("expected .double") }
    }
}
