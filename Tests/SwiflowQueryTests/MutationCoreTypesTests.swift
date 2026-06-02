// Tests/SwiflowQueryTests/MutationCoreTypesTests.swift
import Testing
@testable import SwiflowQuery

@MainActor
private struct Count: Query {
    var queryKey: QueryKey { ["count"] }
    func fetch() async throws -> Int { 0 }
}

@Suite("Mutation/coreTypes")
@MainActor
struct MutationCoreTypesTests {
    @Test func invalidationCasesEquate() {
        #expect(Invalidation.prefix(["a"]) == .prefix(["a"]))
        #expect(Invalidation.exact(["a", 1]) != .prefix(["a", 1]))
    }

    @Test func updateCarriesKeyAndTransforms() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        #expect(edit.key == ["count"])
        #expect((edit.apply(10) as? Int) == 11)
    }

    @Test func updateNoOpsOnAbsentOrMismatchedValue() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        #expect(edit.apply(nil) == nil)            // absent → no-op
        #expect(edit.apply("not an int") == nil)   // type mismatch → no-op
    }
}
