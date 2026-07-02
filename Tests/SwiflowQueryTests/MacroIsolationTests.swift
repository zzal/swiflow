import Testing
import SwiflowQuery

// Compile-as-test for the `@MainActor` memberAttribute role: BARE `@Query` /
// `@Mutation` (NO `: Query` / `: Mutation` on the primary declaration) whose
// witnesses synchronously touch `@MainActor` state must type-check. Without the
// role, the witnesses are nonisolated and this file fails to build:
//   - `fetch` synchronously reading `@MainActor` state, and
//   - `optimistic` synchronously calling the `@MainActor` `OptimisticEdit.update`.

@MainActor enum MainBox { static var value = 7 }

@Query struct IsoQuery {
    @Key var id: Int
    func fetch() async throws -> Int { id + MainBox.value }   // sync read of @MainActor state
}

@Mutation struct IsoMut {
    let id: Int
    static var seq = -1
    func perform(_ x: Int) async throws -> Int { id + x }
    func optimistic(_ x: Int) -> [OptimisticEdit] {
        let t = IsoMut.seq; IsoMut.seq -= 1
        return [.update(IsoQuery(id: id)) { _ in t }]          // sync call of @MainActor update
    }
}

@Suite("Macro @MainActor isolation")
@MainActor
struct MacroIsolationTests {
    @Test("bare @Query/@Mutation with @MainActor-touching witnesses work")
    func bareUsageIsIsolationSafe() async throws {
        #expect(IsoQuery(id: 1).queryKey == ["IsoQuery", .int(1)])
        #expect(try await IsoMut(id: 2).perform(3) == 5)
        #expect(IsoMut(id: 2).optimistic(0).count == 1)
    }
}

// Audit Wave-2 regression gate: a witness the author ALREADY isolated must not
// get a second @MainActor stamped (was: "declaration can not have multiple
// global actor attributes"). Redundant-but-legal explicit isolation compiles.
@Query struct IsoQueryExplicit {
    @Key var id: Int
    @MainActor func fetch() async throws -> Int { id }
}
@Mutation struct IsoMutNonisolatedHelper {
    func perform(_ x: Int) async throws -> Int { x }
    // A nonisolated member must never be stamped either.
    nonisolated func helperConstant() -> Int { 7 }
}
