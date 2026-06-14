// Tests/SwiflowStoreTests/JSONValueEncoderTests.swift
//
// Host-side tests for the Encodable → JSONValue encoder. JavaScriptKit ships a
// `JSValueDecoder` but no encoder, and Foundation's `JSONEncoder` isn't
// available under WASM — `JSONValueEncoder` fills that gap in pure Swift, so it
// is fully testable off-WASM the same way `JSONValue.jsonString` is.
import Testing
import SwiflowFetcher          // JSONValue
@testable import SwiflowStore

@Suite("JSONValueEncoder")
struct JSONValueEncoderTests {

    // Representative shapes the store will round-trip.
    private struct Point: Codable { let x: Int; let y: Int }
    private struct Person: Codable { let name: String; let age: Int; let height: Double; let active: Bool }
    private struct WithOptional: Codable { let a: String; let b: String? }
    private struct Nested: Codable { let id: Int; let point: Point }
    private struct CityLike: Codable {
        let id: Int; let name: String; let latitude: Double; let longitude: Double
        let country: String?; let admin1: String?
    }

    @Test("encodes a flat struct to the matching JSONValue tree")
    func flatStruct() throws {
        let v = try JSONValueEncoder().encode(Point(x: 1, y: 2))
        #expect(v == .object(["x": .int(1), "y": .int(2)]))
    }

    @Test("encodes the primitive families (int, double, bool, string)")
    func primitives() throws {
        let v = try JSONValueEncoder().encode(Person(name: "Ann", age: 30, height: 1.5, active: true))
        #expect(v.jsonString == #"{"active":true,"age":30,"height":1.5,"name":"Ann"}"#)
    }

    @Test("omits nil optionals (encodeIfPresent), keeps present ones")
    func optionals() throws {
        #expect(try JSONValueEncoder().encode(WithOptional(a: "x", b: "y")).jsonString
                == #"{"a":"x","b":"y"}"#)
        #expect(try JSONValueEncoder().encode(WithOptional(a: "x", b: nil)).jsonString
                == #"{"a":"x"}"#)
    }

    @Test("encodes a nested Encodable via encode(_:forKey:)")
    func nestedStruct() throws {
        let v = try JSONValueEncoder().encode(Nested(id: 1, point: Point(x: 2, y: 3)))
        #expect(v.jsonString == #"{"id":1,"point":{"x":2,"y":3}}"#)
    }

    @Test("encodes a top-level array of structs")
    func arrayOfStructs() throws {
        let v = try JSONValueEncoder().encode([Point(x: 1, y: 2), Point(x: 3, y: 4)])
        #expect(v.jsonString == #"[{"x":1,"y":2},{"x":3,"y":4}]"#)
    }

    @Test("encodes a top-level primitive (single-value container)")
    func topLevelPrimitive() throws {
        #expect(try JSONValueEncoder().encode(42).jsonString == "42")
        #expect(try JSONValueEncoder().encode("hi").jsonString == #""hi""#)
    }

    private struct BigID: Codable { let id: UInt64 }

    @Test("integers beyond Int range fall back to double instead of trapping")
    func integerOverflow() throws {
        // UInt64.max exceeds Int on every platform (and Int is only 32-bit on
        // wasm32), so it must be emitted as a double rather than crash `Int(_:)`.
        let v = try JSONValueEncoder().encode(BigID(id: UInt64.max))
        #expect(v == .object(["id": .double(Double(UInt64.max))]))
    }

    @Test("round-trips the City shape the example persists")
    func cityShape() throws {
        let cities = [
            CityLike(id: 6077243, name: "Montréal", latitude: 45.5, longitude: -73.5,
                     country: "Canada", admin1: "Quebec"),
            CityLike(id: -1, name: "My Location", latitude: 1.5, longitude: 2.5,
                     country: nil, admin1: nil),
        ]
        let v = try JSONValueEncoder().encode(cities)
        #expect(v.jsonString == #"[{"admin1":"Quebec","country":"Canada","id":6077243,"latitude":45.5,"longitude":-73.5,"name":"Montréal"},{"id":-1,"latitude":1.5,"longitude":2.5,"name":"My Location"}]"#)
    }
}
