import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

@Suite("Macro/MutationState")
struct MutationStateMacroTests {
    private let macros: [String: Macro.Type] = ["MutationState": MutationStateMacro.self]

    @Test func emitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo
            """,
            expandedSource: """
            var create: CreateTodo

            private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

            var $create: MutationHandle<CreateTodo> {
                MutationHandle(runtime: _create_mutationRuntime, mutation: create)
            }
            """,
            macros: macros
        )
    }
}
