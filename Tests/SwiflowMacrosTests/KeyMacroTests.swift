import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

@Suite("Macro/Key")
struct KeyMacroTests {
    private let macros: [String: Macro.Type] = ["Key": KeyMacro.self]

    @Test("@Key on a stored var is a no-op marker — emits no peers")
    func storedVarIsNoOp() {
        assertMacroExpansion(
            """
            @Key var id: Int
            """,
            expandedSource: """
            var id: Int
            """,
            macros: macros
        )
    }

    @Test("@Key on a stored let is also a no-op marker")
    func storedLetIsNoOp() {
        assertMacroExpansion(
            """
            @Key let slug: String
            """,
            expandedSource: """
            let slug: String
            """,
            macros: macros
        )
    }

    @Test("@Key on a computed property is a placement error")
    func computedPropertyDiagnoses() {
        assertMacroExpansion(
            """
            @Key var id: Int { 0 }
            """,
            expandedSource: """
            var id: Int { 0 }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Key marks a stored property; computed properties cannot be query-key components.",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
}
