import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

@Suite("@ReducerState macro")
struct ReducerStateMacroTests {
    let macros: [String: any Macro.Type] = ["ReducerState": ReducerStateMacro.self]

    @Test("emits the runtime field and the $ projection")
    func emitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout
            """,
            expandedSource: """
            var flow: Checkout

            private let _flow_reducerRuntime = ReducerRuntime<Checkout>()

            var $flow: ReducerHandle<Checkout> {
                ReducerHandle(runtime: _flow_reducerRuntime, reducer: flow)
            }
            """,
            macros: macros)
    }
}
