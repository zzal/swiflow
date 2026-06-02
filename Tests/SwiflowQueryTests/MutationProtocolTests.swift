// Tests/SwiflowQueryTests/MutationProtocolTests.swift
import Testing
@testable import SwiflowQuery

@MainActor
private struct Save: Mutation {
    let sink: @MainActor @Sendable (String) -> Int
    func perform(_ input: String) async throws -> Int { sink(input) }
}

@Suite("Mutation/protocol")
@MainActor
struct MutationProtocolTests {
    @Test func defaultsAreEmpty() {
        let m = Save { _ in 1 }
        #expect(m.optimistic("x").isEmpty)
        #expect(m.invalidations(input: "x", output: 1).isEmpty)
    }

    @Test func performRuns() async throws {
        let m = Save { $0.count }
        let out = try await m.perform("abcd")
        #expect(out == 4)
    }
}
