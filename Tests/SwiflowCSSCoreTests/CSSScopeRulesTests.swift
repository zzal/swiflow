// Tests/SwiflowCSSCoreTests/CSSScopeRulesTests.swift
import Testing
@testable import SwiflowCSSCore

@Suite("CSS scope rules")
struct CSSScopeRulesTests {

    @Test("root-targeting selectors escape component scoping", arguments: [
        ":root", "html", "body",
        ":root[data-theme=\"dark\"]",   // prefix match, not exact
        "html.dark",
        "body > main",
    ])
    func rootSelectorsEscape(_ selector: String) {
        #expect(CSSScopeRules.escapesComponentScoping(selector))
    }

    @Test("case is folded — HTML/BODY/:Root escape too", arguments: [
        "HTML", "BODY", ":ROOT", "Html", ":Root",
    ])
    func caseFolded(_ selector: String) {
        #expect(CSSScopeRules.escapesComponentScoping(selector))
    }

    @Test("everything else is scoped", arguments: [
        ".card", "#id", "button", "div > span",
        ".body-text",        // a class, not the `body` element (starts with `.`)
        "[data-body]",       // attribute selector (starts with `[`)
        "main",
    ])
    func othersAreScoped(_ selector: String) {
        #expect(!CSSScopeRules.escapesComponentScoping(selector))
    }

    // Documented caveat: the rule is a PREFIX match, so a bare type selector
    // that merely begins with html/body (`htmlish`, `body-wrap` as an element)
    // also escapes. This is pre-existing behavior shared verbatim by both scope
    // paths — pinned here so a future "tighten to exact match" is a conscious,
    // both-paths change, not an accident.
    @Test("prefix-match caveat: bare html/body-prefixed type selectors escape", arguments: [
        "htmlish", "bodyfoo",
    ])
    func prefixMatchCaveat(_ selector: String) {
        #expect(CSSScopeRules.escapesComponentScoping(selector))
    }
}
