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
    @Test("Invalidation equality distinguishes .exact from .prefix") func invalidationCasesEquate() {
        #expect(Invalidation.prefix(["a"]) == .prefix(["a"]))
        #expect(Invalidation.exact(["a", 1]) != .prefix(["a", 1]))
    }

    @Test(".update carries the query's key and writes the transformed value") func updateCarriesKeyAndTransforms() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        #expect(edit.key == ["count"])
        guard case .write(let next) = edit.apply(10) else {
            Issue.record("expected .write"); return
        }
        #expect((next as? Int) == 11)
    }

    @Test(".update reports .noValue when the cache holds nothing for the key") func updateReportsNoValueWhenAbsent() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        guard case .noValue = edit.apply(nil) else {
            Issue.record("absent value should report .noValue"); return
        }
    }

    @Test(".update reports .typeMismatch naming both types when the cached value has the wrong type") func updateFlagsTypeMismatchOnWrongType() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        guard case .typeMismatch(let expected, let actual) = edit.apply("not an int") else {
            Issue.record("wrong cached type should report .typeMismatch"); return
        }
        #expect(expected.contains("Int"))
        #expect(actual.contains("String"))
    }
}
