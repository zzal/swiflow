// Tests/SwiflowHTTPTests/JSONValueTests.swift
import Testing
@testable import SwiflowHTTP

@Suite("JSONValue")
struct JSONValueTests {
    @Test("literals map to the expected cases")
    func literals() {
        #expect(JSONValue("x") == .string("x"))
        #expect(JSONValue(3) == .int(3))
        #expect(JSONValue(2.5) == .double(2.5))
        #expect(JSONValue(true) == .bool(true))
        #expect(JSONValue(nilLiteral: ()) == .null)

        let arr: JSONValue = [1, "two", true]
        #expect(arr == .array([.int(1), .string("two"), .bool(true)]))

        let obj: JSONValue = ["title": "Buy milk", "done": false, "tags": ["a", "b"]]
        #expect(obj == .object([
            "title": .string("Buy milk"),
            "done": .bool(false),
            "tags": .array([.string("a"), .string("b")]),
        ]))
    }

    @Test("dictionary literal: last value wins on duplicate keys (no trap)")
    func duplicateKeys() {
        let obj: JSONValue = ["k": 1, "k": 2]
        #expect(obj == .object(["k": .int(2)]))
    }

    @Test("jsonString encodes primitives")
    func primitives() {
        #expect(JSONValue.null.jsonString == "null")
        #expect(JSONValue.bool(true).jsonString == "true")
        #expect(JSONValue.bool(false).jsonString == "false")
        #expect(JSONValue.int(42).jsonString == "42")
        #expect(JSONValue.int(-7).jsonString == "-7")
        #expect(JSONValue.double(2.5).jsonString == "2.5")
        #expect(JSONValue.string("hi").jsonString == "\"hi\"")
    }

    @Test("jsonString sorts object keys and nests arrays/objects")
    func composites() {
        let v: JSONValue = ["b": 2, "a": 1]
        #expect(v.jsonString == #"{"a":1,"b":2}"#)

        let nested: JSONValue = ["list": [1, 2], "obj": ["x": true]]
        #expect(nested.jsonString == #"{"list":[1,2],"obj":{"x":true}}"#)

        #expect(JSONValue.array([.string("a"), .null]).jsonString == #"["a",null]"#)
    }

    @Test("jsonString escapes strings per RFC 8259")
    func escaping() {
        #expect(JSONValue.string("a\"b").jsonString == #""a\"b""#)
        #expect(JSONValue.string("a\\b").jsonString == #""a\\b""#)
        #expect(JSONValue.string("line1\nline2").jsonString == #""line1\nline2""#)
        #expect(JSONValue.string("tab\there").jsonString == #""tab\there""#)
        // Control char U+0001 becomes a backslash-u escape. The control char
        // and the expected escape are assembled from plain ASCII so no raw
        // control byte or 4-hex escape lands in this source file.
        let control = String(UnicodeScalar(UInt8(1)))
        let expected = "\"" + "\\" + "u0001" + "\""
        #expect(JSONValue.string(control).jsonString == expected)
        // Non-ASCII passes through verbatim.
        #expect(JSONValue.string("e \u{2014} pi").jsonString == "\"e \u{2014} pi\"")
    }
}
