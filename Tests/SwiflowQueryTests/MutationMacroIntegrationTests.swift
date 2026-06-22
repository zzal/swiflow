import Testing
import SwiflowQuery

// End-to-end exercise of the real `@Mutation` macro (declaration + plugin +
// `Mutation` conformance + `InitSynthesis`), complementing the expansion-level
// golden tests in `Tests/SwiflowMacrosTests/MutationMacroTests`. That this
// file *compiles* is itself a test: a wrong conformance or duplicated init would
// fail to build.

@Mutation struct ITMRename {
    let id: Int                                    // captured dependency
    func perform(_ newName: String) async throws -> String { "\(id):\(newName)" }
}

@Mutation struct ITMNoDeps {
    func perform(_ x: Int) async throws -> Int { x * 2 }
}

// Migration shape: declares `: Mutation` AND a hand-written `init`. If
// `@Mutation` double-conformed or duplicated the init, this would NOT compile
// — so building this struct verifies the conditional-conformance + suppression
// guards.
@Mutation struct ITMExplicit: Mutation {
    let id: Int
    init(id: Int) { self.id = id }
    func perform(_ x: Int) async throws -> Int { id + x }
}

@Suite("Mutation integration")
@MainActor
struct MutationMacroIntegrationTests {
    @Test("captured dependency becomes a memberwise-init parameter; type conforms to Mutation")
    func capturedDependency() async throws {
        #expect(try await ITMRename(id: 5).perform("bob") == "5:bob")
    }

    @Test("no stored deps → synthesized empty init; still a Mutation")
    func noStoredDeps() async throws {
        #expect(try await ITMNoDeps().perform(21) == 42)
    }

    @Test("hand-written init is preserved; : Mutation does not double-conform")
    func explicitConformanceAndInit() async throws {
        #expect(try await ITMExplicit(id: 10).perform(5) == 15)
    }

    @Test("a synthesized type is usable everywhere a Mutation is required")
    func conformsToMutation() async throws {
        func run<M: Mutation>(_ m: M, _ input: M.Input) async throws -> M.Output {
            try await m.perform(input)
        }
        #expect(try await run(ITMNoDeps(), 3) == 6)
    }
}
