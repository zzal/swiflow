import Testing
@testable import Swiflow

@Suite("#css — end-to-end expansion and rendering")
struct CSSMacroIntegrationTests {

    @Test("#css renders scoped body, host mapping, and hoisted keyframes")
    func endToEnd() {
        let sheet: CSSSheet = #css("""
            :host { display: block; }
            .row { display: grid; }
            @keyframes spin { to { transform: rotate(360deg); } }
            """)
        let out = sheet.cssString(scopeClass: "swiflow-X")
        #expect(out.contains(".swiflow-X {"))
        #expect(out.contains("& { display: block; }"))
        #expect(out.contains(".row { display: grid; }"))
        #expect(out.contains("@keyframes spin"))
        // The keyframes block is NOT inside the scope wrapper: the wrapper's
        // closing brace precedes the @keyframes header.
        #expect(out.contains("}\n@keyframes"))
    }

    @Test("#css composes with the builder DSL via +")
    func composesWithDSL() {
        let sheet = #css(".a { color: red; }") + css { rule(".b") { .margin("0") } }
        let out = sheet.cssString(scopeClass: "swiflow-T")
        #expect(out.contains(".swiflow-T {\n  .a { color: red; }\n}"))
        #expect(out.contains(".swiflow-T .b {"))
    }
}
