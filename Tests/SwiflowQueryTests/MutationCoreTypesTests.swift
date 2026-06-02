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
        guard case .write(let next) = edit.apply(10) else {
            Issue.record("expected .write"); return
        }
        #expect((next as? Int) == 11)
    }

    @Test func updateReportsNoValueWhenAbsent() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        guard case .noValue = edit.apply(nil) else {
            Issue.record("absent value should report .noValue"); return
        }
    }

    @Test func updateFlagsTypeMismatchOnWrongType() {
        let edit = OptimisticEdit.update(Count()) { $0 + 1 }
        guard case .typeMismatch(let expected, let actual) = edit.apply("not an int") else {
            Issue.record("wrong cached type should report .typeMismatch"); return
        }
        #expect(expected.contains("Int"))
        #expect(actual.contains("String"))
    }
}
