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

    // MARK: Split diagnostics (audit III Wave-1 #4) — the folded
    // requiresVarWithType told a `let` author to add a type annotation.
    // Port @State's tailored-message standard.

    func testRejectsLet() {
        assertMacroExpansion(
            """
            @MutationState let create: CreateTodo
            """,
            expandedSource: """
            let create: CreateTodo
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState requires a `var` (e.g. `@MutationState var create: CreateTodo`).",
                    line: 1, column: 1, severity: .error,
                    fixIts: [FixItSpec(message: "Replace 'let' with 'var'")]
                ),
            ],
            macros: testMacros
        )
    }

    func testRequiresTypeAnnotation() {
        assertMacroExpansion(
            """
            @MutationState var create = CreateTodo()
            """,
            expandedSource: """
            var create = CreateTodo()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState requires an explicit type annotation (e.g. `@MutationState var create: CreateTodo`).",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo {
                didSet { print("user") }
            }
            """,
            expandedSource: """
            var create: CreateTodo {
                didSet { print("user") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState properties cannot declare their own didSet — the property only stores the mutation value; observe runs via the `$`-prefixed handle (e.g. `$create.isPending`).",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testComputedPropertyIsRejected() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo {
                CreateTodo()
            }
            """,
            expandedSource: """
            var create: CreateTodo {
                CreateTodo()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @MutationState if this isn't meant to be a mutation handle.",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Explicit get/set must hit the same computed-property diagnostic as the
    // getter-only shorthand (pins the shared isComputedProperty branch
    // through THIS macro's call site, not just @State's).
    func testComputedPropertyWithGetSetIsRejected() {
        assertMacroExpansion(
            """
            @MutationState var create: CreateTodo {
                get { CreateTodo() }
                set { }
            }
            """,
            expandedSource: """
            var create: CreateTodo {
                get { CreateTodo() }
                set { }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @MutationState if this isn't meant to be a mutation handle.",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // A tuple pattern is one binding declaring several properties — the
    // one-property-per-declaration advice is the fix, so it routes to
    // requiresSingleBinding.
    func testTuplePatternRejected() {
        assertMacroExpansion(
            """
            @MutationState var (add, remove): (AddTodo, RemoveTodo)
            """,
            expandedSource: """
            var (add, remove): (AddTodo, RemoveTodo)
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationState must be applied to a single property declaration; declare each mutation separately (e.g. `@MutationState var add: AddTodo` on its own line).",
                    line: 1, column: 1, severity: .error
                ),
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
