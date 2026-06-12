import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "css": CSSMacro.self,
]

final class CSSMacroTests: XCTestCase {

    // Test 1: plain rule — single scopedBlock entry.
    func testSimpleRuleExpandsToScopedBlock() {
        assertMacroExpansion(
            #"""
            let sheet = #css(".row { display: grid; }")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [.scopedBlock(".row { display: grid; }")])
            """#,
            macros: testMacros
        )
    }

    // Test 2: scoped segments merge into ONE block (joined by a blank line);
    // hoisted at-rules become .raw entries; the block sits at the position
    // of the first scoped segment.
    func testHoistingAndMerging() {
        assertMacroExpansion(
            #"""
            let sheet = #css(".a { color: red; } @keyframes spin { to { opacity: 0; } } .b { margin: 0; }")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [.scopedBlock(".a { color: red; }\n\n.b { margin: 0; }"), .raw("@keyframes spin { to { opacity: 0; } }")])
            """#,
            macros: testMacros
        )
    }

    // Test 3: :host rewriting reaches the emitted block.
    func testHostRewriting() {
        assertMacroExpansion(
            #"""
            let sheet = #css(":host { display: block; }")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [.scopedBlock("& { display: block; }")])
            """#,
            macros: testMacros
        )
    }

    // Test 4: empty literal — valid, empty sheet.
    func testEmptyLiteral() {
        assertMacroExpansion(
            #"""
            let sheet = #css("")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            macros: testMacros
        )
    }

    // Test 5: parser diagnostics surface as compile errors anchored on the literal.
    func testStructuralErrorIsDiagnosed() {
        assertMacroExpansion(
            #"""
            let sheet = #css(".row { display grid; }")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "CSS error at line 1, column 8: expected 'property: value' — got 'display grid'",
                    line: 1, column: 18)
            ],
            macros: testMacros
        )
    }

    // Test 6: interpolation is rejected with the custom-property guidance.
    func testInterpolationIsRejected() {
        assertMacroExpansion(
            #"""
            let sheet = #css(".row { color: \(accent); }")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "#css requires a static string literal — pass dynamic values via CSS custom properties (.style(\"--x\", value)) and read them with var(--x)",
                    line: 1, column: 18)
            ],
            macros: testMacros
        )
    }

    // Test 7: non-literal argument is rejected the same way.
    func testNonLiteralIsRejected() {
        assertMacroExpansion(
            #"""
            let sheet = #css(someString)
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "#css requires a static string literal — pass dynamic values via CSS custom properties (.style(\"--x\", value)) and read them with var(--x)",
                    line: 1, column: 18)
            ],
            macros: testMacros
        )
    }

    // Test 8: @import is a compile error with index.html guidance.
    func testImportIsRejected() {
        assertMacroExpansion(
            #"""
            let sheet = #css("@import url(x.css);")
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "CSS error at line 1, column 1: @import is not supported in component sheets — load global CSS from index.html",
                    line: 1, column: 18)
            ],
            macros: testMacros
        )
    }
}
