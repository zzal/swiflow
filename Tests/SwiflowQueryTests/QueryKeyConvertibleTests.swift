import Testing
@testable import SwiflowQuery

@Suite("QueryKeyConvertible")
struct QueryKeyConvertibleTests {
    @Test("Int keys as a single .int component")
    func intKeys() {
        #expect(5.keyComponents == [.int(5)])
    }

    @Test("String keys as a single .string component")
    func stringKeys() {
        #expect("users".keyComponents == [.string("users")])
    }

    @Test("Bool keys as a stable .string — never .int, so it cannot collide with an integer id")
    func boolKeys() {
        #expect(true.keyComponents == [.string("true")])
        #expect(false.keyComponents == [.string("false")])
        // A Bool key and an Int key at the same position stay distinct.
        #expect(true.keyComponents != 1.keyComponents)
    }

    @Test("String-raw enums key by their raw value via the RawRepresentable conformance")
    func stringRawEnumKeys() {
        #expect(Window.day.keyComponents == [.string("day")])
    }

    @Test("Int-raw enums key by their raw value")
    func intRawEnumKeys() {
        #expect(Priority.high.keyComponents == [.int(2)])
    }

    @Test("_qkc dispatches to keyComponents (the helper @Query's expansion emits)")
    func qkcHelper() {
        #expect(_qkc(5) == [.int(5)])
        #expect(_qkc("users") == [.string("users")])
        #expect(_qkc(Window.week) == [.string("week")])
    }
}

private enum Window: String, QueryKeyConvertible { case hour, day, week }
private enum Priority: Int, QueryKeyConvertible { case low = 1, high = 2 }
