import XCTest
@testable import SwiflowMacrosPlugin

final class CSSStructuralParserTests: XCTestCase {

    // MARK: - Happy path & segmentation

    func testSimpleRuleIsScoped() {
        let r = CSSStructuralParser.parse(".row { display: grid; }")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(".row { display: grid; }")])
    }

    func testMultipleRulesProduceMultipleScopedSegments() {
        let r = CSSStructuralParser.parse(".a { color: red; }\n.b { margin: 0; }")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(".a { color: red; }"), .scoped(".b { margin: 0; }")])
    }

    func testUnknownPropertiesAndValuesPassThrough() {
        // Structural validation only — properties CSS invents next year must work.
        let r = CSSStructuralParser.parse(".x { text-wrap: pretty; corner-shape: squircle; }")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(".x { text-wrap: pretty; corner-shape: squircle; }")])
    }

    func testNestedRulesStayInsideOneSegment() {
        let css = ".row { display: grid; .when { color: gray; } &:hover { background: blue; } }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testMediaQueryStaysScoped() {
        let css = "@media (max-width: 600px) { .row { grid-template-columns: 1fr; } }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testCommentsAndStringsAreOpaque() {
        let css = ".x { /* } not a close */ content: \"}\"; color: red; }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testEmptyInputIsValid() {
        let r = CSSStructuralParser.parse("  \n  ")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [])
    }

    // MARK: - Hoisting classification

    func testKeyframesAreHoisted() {
        let css = "@keyframes spin { to { transform: rotate(360deg); } }\n.dot { animation: spin 1s; }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [
            .hoisted("@keyframes spin { to { transform: rotate(360deg); } }"),
            .scoped(".dot { animation: spin 1s; }"),
        ])
    }

    func testFontFaceAndPropertyAreHoisted() {
        let r = CSSStructuralParser.parse(
            "@font-face { font-family: X; src: url(x.woff2); }\n@property --hue { syntax: \"<angle>\"; inherits: false; initial-value: 0deg; }")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments.count, 2)
        for segment in r.segments {
            if case .scoped = segment { XCTFail("expected hoisted, got \(segment)") }
        }
    }

    func testLayerStatementHoistedButLayerBlockScoped() {
        let r1 = CSSStructuralParser.parse("@layer base, components;")
        XCTAssertEqual(r1.segments, [.hoisted("@layer base, components;")])
        let r2 = CSSStructuralParser.parse("@layer base { .x { color: red; } }")
        XCTAssertEqual(r2.segments, [.scoped("@layer base { .x { color: red; } }")])
    }

    func testRootHtmlBodyEscapeScoping() {
        let r = CSSStructuralParser.parse(
            ":root { --bg: white; }\nhtml { box-sizing: border-box; }\nbody.dark { margin: 0; }\n.app { color: red; }")
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [
            .hoisted(":root { --bg: white; }"),
            .hoisted("html { box-sizing: border-box; }"),
            .hoisted("body.dark { margin: 0; }"),
            .scoped(".app { color: red; }"),
        ])
    }

    // MARK: - Rejected at-rules

    func testImportIsRejected() {
        let r = CSSStructuralParser.parse("@import url(\"x.css\");")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "@import is not supported in component sheets — load global CSS from index.html",
                  line: 1, column: 1)
        ])
    }

    // MARK: - Structural diagnostics

    func testMissingColonInDeclaration() {
        let r = CSSStructuralParser.parse(".row { display grid; }")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "expected 'property: value' — got 'display grid'", line: 1, column: 8)
        ])
    }

    func testMissingColonInLastDeclarationWithoutSemicolon() {
        let r = CSSStructuralParser.parse(".row {\n  color: red;\n  display grid\n}")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "expected 'property: value' — got 'display grid'", line: 3, column: 3)
        ])
    }

    func testUnclosedBrace() {
        let r = CSSStructuralParser.parse(".row { color: red;")
        XCTAssertEqual(r.diagnostics, [.init(message: "unclosed '{'", line: 1, column: 6)])
    }

    func testUnmatchedClosingBrace() {
        let r = CSSStructuralParser.parse("} .x { color: red; }")
        XCTAssertEqual(r.diagnostics, [.init(message: "unmatched '}'", line: 1, column: 1)])
    }

    func testMismatchedBracket() {
        let r = CSSStructuralParser.parse(".x { width: calc(100% - 2rem]; }")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "mismatched ']' — expected ')' to close '(' opened at line 1",
                  line: 1, column: 29)
        ])
    }

    func testUnterminatedComment() {
        let r = CSSStructuralParser.parse("/* never closed")
        XCTAssertEqual(r.diagnostics, [.init(message: "unterminated comment", line: 1, column: 1)])
    }

    func testUnterminatedString() {
        let r = CSSStructuralParser.parse(".x { content: \"oops\n; }")
        XCTAssertEqual(r.diagnostics, [.init(message: "unterminated string", line: 1, column: 15)])
    }

    func testSelectorWithoutBlockAtEOF() {
        let r = CSSStructuralParser.parse(".row")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "unexpected end of CSS — expected '{'", line: 1, column: 1)
        ])
    }

    func testStraySemicolonAtTopLevel() {
        let r = CSSStructuralParser.parse(".x; { color: red; }")
        XCTAssertEqual(r.diagnostics, [
            .init(message: "unexpected ';' — expected a '{' block after the selector", line: 1, column: 3)
        ])
    }

    // MARK: - Unquoted url() tokens

    func testUnquotedURLWithBracesAndSemicolonsIsOpaque() {
        // Per the CSS url-token rules, an unquoted url() may contain {, }, ;, ,
        // — data URIs are the classic case. None of it is structure.
        let css = ".x { background: url(data:image/png;base64,iVBO{R}w0=); }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testUnquotedURLWithApostrophePassesThrough() {
        // Technically a bad-url-token per spec, but validity is the browser's
        // call — the structural parser only needs to not false-error.
        let css = ".x { background: url(images/it's.png); }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testQuotedURLStillUsesStringScanning() {
        let css = ".x { background: url(\"a}b.png\"); }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testFunctionNamesEndingInURLAreNotURLTokens() {
        // -moz-url( / no-url( must not trigger the opaque consumption;
        // their parens get normal balance tracking.
        let css = ".x { background: imitation-url(\"a.png\"); }"
        let r = CSSStructuralParser.parse(css)
        XCTAssertEqual(r.diagnostics, [])
        XCTAssertEqual(r.segments, [.scoped(css)])
    }

    func testUnterminatedUnquotedURL() {
        let r = CSSStructuralParser.parse(".x { background: url(oops")
        XCTAssertEqual(r.diagnostics, [.init(message: "unterminated url()", line: 1, column: 18)])
    }

    // MARK: - :host rewriting

    func testBareHostBecomesAmpersand() {
        let r = CSSStructuralParser.parse(":host { display: block; }")
        XCTAssertEqual(r.segments, [.scoped("& { display: block; }")])
    }

    func testFunctionalHostBecomesIsSelector() {
        let r = CSSStructuralParser.parse(":host(.dark) .row { color: white; }")
        XCTAssertEqual(r.segments, [.scoped("&:is(.dark) .row { color: white; }")])
    }

    func testHostInsideNestedMediaIsRewritten() {
        let r = CSSStructuralParser.parse("@media (max-width: 600px) { :host { padding: 0; } }")
        XCTAssertEqual(r.segments, [.scoped("@media (max-width: 600px) { & { padding: 0; } }")])
    }

    func testHostContextAndStringsAreNotRewritten() {
        // :host-context shares the ":host" prefix; string content is opaque.
        let r = CSSStructuralParser.parse(".x { content: \":host\"; } :host-context(.dark) { color: red; }")
        XCTAssertEqual(r.segments, [
            .scoped(".x { content: \":host\"; }"),
            .scoped(":host-context(.dark) { color: red; }"),
        ])
    }

    func testHostIsNotRewrittenInHoistedSegments() {
        // Hoisted rules render outside the wrapper, where '&' has no meaning —
        // the :host text must survive untouched.
        let r = CSSStructuralParser.parse("body :host { color: red; }")
        XCTAssertEqual(r.segments, [.hoisted("body :host { color: red; }")])
    }

    func testBareHostWithTrailingPseudoClass() {
        let r = CSSStructuralParser.parse(":host:hover { background: blue; }")
        XCTAssertEqual(r.segments, [.scoped("&:hover { background: blue; }")])
    }

    func testFunctionalHostWithTrailingPseudoClass() {
        let r = CSSStructuralParser.parse(":host(.dark):hover { opacity: .8; }")
        XCTAssertEqual(r.segments, [.scoped("&:is(.dark):hover { opacity: .8; }")])
    }
}
