// XCTest, NOT swift-testing: `assertMacroExpansion` reports via XCTFail,
// which swift-testing silently swallows — a @Test golden here passes even
// with a deliberately wrong expectation (verified 2026-07-02). Keep every
// assertMacroExpansion golden in an XCTestCase.
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "MutationState": MutationStateMacro.self,
]

final class MutationStateMacroTests: XCTestCase {

    // @MutationState expands to a private runtime plus a $-prefixed
    // MutationHandle projection.
    func testEmitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo
            """,
            expandedSource: """
            var create: CreateTodo

            @MainActor private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

            @MainActor var $create: MutationHandle<CreateTodo> {
                MutationHandle(runtime: _create_mutationRuntime, mutation: create)
            }
            """,
            macros: testMacros
        )
    }

    // Multi-binding. HARNESS/COMPILER DIVERGENCE (see StateMacroTests):
    // the harness refuses peer-on-multi-binding itself and never invokes our
    // expansion; the REAL compiler silently runs the peer once per binding —
    // where our requiresSingleBinding guard fires (host-compile verified;
    // recorded in the PR since a committed test can't assert a compile failure).
    func testRejectsMultiBinding() {
        assertMacroExpansion(
            """
            final class Comp {
                @MutationState var add: AddTodo = AddTodo(), remove: RemoveTodo = RemoveTodo()
            }
            """,
            expandedSource: """
            final class Comp {
                var add: AddTodo = AddTodo(), remove: RemoveTodo = RemoveTodo()
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "peer macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
            ],
            macros: testMacros
        )
    }

    // Access propagation (audit Wave-2): $create copies the property's access;
    // the backing runtime stays private (implementation detail).
    func testPublicMutationStateEmitsPublicProjection() {
        assertMacroExpansion(
            """
            @MutationState public var create: CreateTodo
            """,
            expandedSource: """
            public var create: CreateTodo

            @MainActor private let _create_mutationRuntime = MutationRuntime<CreateTodo>()

            @MainActor public var $create: MutationHandle<CreateTodo> {
                MutationHandle(runtime: _create_mutationRuntime, mutation: create)
            }
            """,
            macros: testMacros
        )
    }
}
