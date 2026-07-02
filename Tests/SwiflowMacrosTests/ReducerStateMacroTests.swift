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
