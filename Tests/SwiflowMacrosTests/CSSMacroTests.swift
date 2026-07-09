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
                    line: 1, column: 26)   // anchored at the offending token (CSS col 8), not the literal start
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
                    line: 1, column: 19)   // anchored at CSS col 1 (literal content start)
            ],
            macros: testMacros
        )
    }

    // Test 9: CSS containing a double-quote inside a regular "…" literal.
    // NOTE (actual-emission adjustment): plain.content.text returns raw token
    // text, so \"x\" arrives at the CSS parser as backslash + quote + x +
    // backslash + quote. skipString() treats the backslash as a CSS escape and
    // consumes the quote as the escaped char, leaving no closing quote → the
    // CSS parser emits "unterminated string" and the macro returns an empty
    // sheet. Use a raw #"…"# or ##"…"## literal to avoid this:
    //   #css(#"a::after { content: "x"; }"#)   ← correct form
    func testEmbeddedDoubleQuoteSurvivesEmission() {
        assertMacroExpansion(
            ##"""
            let sheet = #css("a::after { content: \"x\"; }")
            """##,
            expandedSource: ##"""
            let sheet = CSSSheet(entries: [])
            """##,
            diagnostics: [
                DiagnosticSpec(
                    message: "CSS error at line 1, column 22: unterminated string",
                    line: 1, column: 40)   // anchored at the offending token (CSS col 22)
            ],
            macros: testMacros
        )
    }

    // Test 10: multiline """ literal — indentation is stripped per Swift rules
    // and the de-indented CSS passes through.
    func testMultilineLiteralIndentationStripped() {
        assertMacroExpansion(
            #"""
            let sheet = #css("""
                .row {
                  display: grid;
                }
                """)
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [.scopedBlock(".row {\n  display: grid;\n}")])
            """#,
            macros: testMacros
        )
    }

    // Test 11: backslash passthrough inside a regular "…" literal.
    // NOTE (actual-emission adjustment): same raw-token-text caveat as Test 9.
    // "\\2014" in a regular literal arrives at the CSS parser as the three
    // characters \, 2, 0, 1, 4 preceded by a `\"` pair; skipString() consumes
    // the leading `\"` as a CSS-escaped quote and then never finds the closing
    // quote → unterminated string. Use a raw ##"…"## literal instead:
    //   #css(##"a::after { content: "\2014"; }"##)   ← correct form
    func testBackslashPassesThroughUncooked() {
        assertMacroExpansion(
            ##"""
            let sheet = #css("a::after { content: \"\\2014\"; }")
            """##,
            expandedSource: ##"""
            let sheet = CSSSheet(entries: [])
            """##,
            diagnostics: [
                DiagnosticSpec(
                    message: "CSS error at line 1, column 22: unterminated string",
                    line: 1, column: 40)   // anchored at the offending token (CSS col 22)
            ],
            macros: testMacros
        )
    }

    // The anchor tracks BOTH line and column into a multi-line literal: the
    // error is on the third source line, and the gutter lands there.
    func testDiagnosticAnchorsAtOffendingLineInMultilineLiteral() {
        assertMacroExpansion(
            #"""
            let sheet = #css("""
            .a { color: red; }
            .b { display grid; }
            """)
            """#,
            expandedSource: #"""
            let sheet = CSSSheet(entries: [])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "CSS error at line 2, column 6: expected 'property: value' — got 'display grid'",
                    line: 3, column: 6)
            ],
            macros: testMacros
        )
    }
}
