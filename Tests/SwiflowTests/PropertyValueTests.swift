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
}
