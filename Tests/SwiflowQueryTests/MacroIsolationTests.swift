import Testing
import SwiflowQuery

// Compile-as-test for the `@MainActor` memberAttribute role: BARE `@QueryType` /
// `@MutationType` (NO `: Query` / `: Mutation` on the primary declaration) whose
// witnesses synchronously touch `@MainActor` state must type-check. Without the
// role, the witnesses are nonisolated and this file fails to build:
//   - `fetch` synchronously reading `@MainActor` state, and
//   - `optimistic` synchronously calling the `@MainActor` `OptimisticEdit.update`.

@MainActor enum MainBox { static var value = 7 }

@QueryType struct IsoQuery {
    @Key var id: Int
    func fetch() async throws -> Int { id + MainBox.value }   // sync read of @MainActor state
}

@MutationType struct IsoMut {
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
    @Test("bare @QueryType/@MutationType with @MainActor-touching witnesses work")
    func bareUsageIsIsolationSafe() async throws {
        #expect(IsoQuery(id: 1).queryKey == ["IsoQuery", .int(1)])
        #expect(try await IsoMut(id: 2).perform(3) == 5)
        #expect(IsoMut(id: 2).optimistic(0).count == 1)
    }
}
