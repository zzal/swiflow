// XCTest, NOT swift-testing: `assertMacroExpansion` reports via XCTFail,
// which swift-testing silently swallows — a @Test golden here passes even
// with a deliberately wrong expectation (verified 2026-07-02). Keep every
// assertMacroExpansion golden in an XCTestCase.
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "ReducerState": ReducerStateMacro.self,
]

final class ReducerStateMacroTests: XCTestCase {

    // Emits the runtime field and the $ projection.
    func testEmitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout
            """,
            expandedSource: """
            var flow: Checkout

            @MainActor private let _flow_reducerRuntime = ReducerRuntime<Checkout>()

            @MainActor var $flow: ReducerHandle<Checkout> {
                ReducerHandle(runtime: _flow_reducerRuntime, reducer: flow)
            }
            """,
            macros: testMacros)
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
                @ReducerState var flow: Checkout = Checkout(), wizard: Signup = Signup()
            }
            """,
            expandedSource: """
            final class Comp {
                var flow: Checkout = Checkout(), wizard: Signup = Signup()
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "peer macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
            ],
            macros: testMacros
        )
    }

    // MARK: Split diagnostics (audit III Wave-1 #4) — mirror of the
    // @MutationState suite; the folded requiresVarWithType told a `let`
    // author to add a type annotation.

    func testRejectsLet() {
        assertMacroExpansion(
            """
            @ReducerState let flow: Checkout
            """,
            expandedSource: """
            let flow: Checkout
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState requires a `var` (e.g. `@ReducerState var flow: Checkout`).",
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
            @ReducerState var flow = Checkout()
            """,
            expandedSource: """
            var flow = Checkout()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState requires an explicit type annotation (e.g. `@ReducerState var flow: Checkout`).",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout {
                didSet { print("user") }
            }
            """,
            expandedSource: """
            var flow: Checkout {
                didSet { print("user") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState properties cannot declare their own didSet — the property only stores the reducer value; state lives in the runtime, read via the `$`-prefixed handle (e.g. `$flow.state`).",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testComputedPropertyIsRejected() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout {
                Checkout()
            }
            """,
            expandedSource: """
            var flow: Checkout {
                Checkout()
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @ReducerState if this isn't meant to be a reducer handle.",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Explicit get/set must hit the same computed-property diagnostic as the
    // getter-only shorthand (pins the shared isComputedProperty branch
    // through THIS macro's call site).
    func testComputedPropertyWithGetSetIsRejected() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout {
                get { Checkout() }
                set { }
            }
            """,
            expandedSource: """
            var flow: Checkout {
                get { Checkout() }
                set { }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @ReducerState if this isn't meant to be a reducer handle.",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // A tuple pattern is one binding declaring several properties — routes to
    // requiresSingleBinding (one-property-per-declaration is the fix).
    func testTuplePatternRejected() {
        assertMacroExpansion(
            """
            @ReducerState var (flow, wizard): (Checkout, Signup)
            """,
            expandedSource: """
            var (flow, wizard): (Checkout, Signup)
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ReducerState must be applied to a single property declaration; declare each reducer separately (e.g. `@ReducerState var flow: Checkout` on its own line).",
                    line: 1, column: 1, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Access propagation (audit Wave-2): mirror of the @MutationState test.
    func testPackageReducerStateEmitsPackageProjection() {
        assertMacroExpansion(
            """
            @ReducerState package var flow: Checkout
            """,
            expandedSource: """
            package var flow: Checkout

            @MainActor private let _flow_reducerRuntime = ReducerRuntime<Checkout>()

            @MainActor package var $flow: ReducerHandle<Checkout> {
                ReducerHandle(runtime: _flow_reducerRuntime, reducer: flow)
            }
            """,
            macros: testMacros
        )
    }
}
