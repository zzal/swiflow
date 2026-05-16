import Testing
@testable import Swiflow

@Suite("PatchPayload")
struct PatchPayloadTests {
    @Test("Equality compares op and fields")
    func equality() {
        let a = PatchPayload(op: "createElement", fields: [
            "handle": .int(0),
            "tag": .string("div"),
        ])
        let b = PatchPayload(op: "createElement", fields: [
            "handle": .int(0),
            "tag": .string("div"),
        ])
        #expect(a == b)
    }

    @Test("Different ops are unequal")
    func differentOps() {
        let a = PatchPayload(op: "createElement", fields: [:])
        let b = PatchPayload(op: "createText", fields: [:])
        #expect(a != b)
    }

    @Test("Different fields are unequal")
    func differentFields() {
        let a = PatchPayload(op: "createElement", fields: ["tag": .string("div")])
        let b = PatchPayload(op: "createElement", fields: ["tag": .string("span")])
        #expect(a != b)
    }

    @Test("Field cases discriminate by type")
    func fieldDiscrimination() {
        #expect(PatchPayload.Field.int(1) != PatchPayload.Field.string("1"))
        #expect(PatchPayload.Field.int(1) == PatchPayload.Field.int(1))
        #expect(PatchPayload.Field.property(.bool(true)) == PatchPayload.Field.property(.bool(true)))
        #expect(PatchPayload.Field.property(.bool(true)) != PatchPayload.Field.property(.bool(false)))
    }
}
