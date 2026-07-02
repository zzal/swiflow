import Foundation
import Testing
@testable import Swiflow

@Suite("CSSSheet — serialization")
struct CSSSheetTests {

    @Test("plain class selector is scoped")
    func plainClassScoped() {
        let sheet = css {
            rule(".root") {
                padding("1rem")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Card")
        #expect(result.contains(".swiflow-Card .root {"))
        #expect(result.contains("padding: 1rem;"))
    }

    @Test("pseudo-class is scoped")
    func pseudoClassScoped() {
        let sheet = css {
            rule(".title:hover") {
                color("#fff")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Btn")
        #expect(result.contains(".swiflow-Btn .title:hover {"))
    }

    @Test(":root selector is NOT scoped")
    func rootNotScoped() {
        let sheet = css {
            rule(":root") {
                cssVar("--bg", "#fff")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix(":root {"))
        #expect(!result.contains("swiflow-T"))
    }

    @Test("html selector is NOT scoped")
    func htmlNotScoped() {
        let sheet = css { rule("html") { property("box-sizing", "border-box") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix("html {"))
    }

    @Test("body selector is NOT scoped")
    func bodyNotScoped() {
        let sheet = css { rule("body") { margin("0") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix("body {"))
    }

    @Test("@keyframes are global (not scoped)")
    func keyframesGlobal() {
        let sheet = css {
            keyframes("slide-in") {
                from { opacity("0") }
                to   { opacity("1") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("@keyframes slide-in {"))
        #expect(!result.contains("swiflow-T"))
    }

    @Test("property() emits custom property declaration")
    func customPropertyDeclaration() {
        let sheet = css {
            rule(":root") {
                property("--primary", "#4a90e2")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("--primary: #4a90e2;"))
    }

    @Test("cssVar() aliases property for custom properties")
    func cssVarAliasesProperty() {
        let sheet = css {
            rule(":root") {
                cssVar("--primary", "#4a90e2")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("--primary: #4a90e2;"))
    }

    @Test("at() produces percent keyframe stop")
    func atPercentStop() {
        let sheet = css {
            keyframes("pulse") {
                from  { opacity("1") }
                at(50) { opacity("0.4") }
                to    { opacity("1") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("50% {"))
    }

    @Test("multiple rules serialized in order")
    func multipleRulesOrdered() throws {
        let sheet = css {
            rule(".a") { color("red") }
            rule(".b") { color("blue") }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        let aRange = try #require(result.range(of: ".swiflow-T .a {"))
        let bRange = try #require(result.range(of: ".swiflow-T .b {"))
        #expect(aRange.lowerBound < bRange.lowerBound)
    }

    @Test("empty sheet produces empty string")
    func emptySheet() {
        let sheet = css {}
        #expect(sheet.cssString(scopeClass: "swiflow-T") == "")
    }

    @Test("class-leading selector emits dual (compound + descendant) selector")
    func classLeadingDualSelector() {
        let sheet = css { rule(".card") { padding("1rem") } }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.contains(".swiflow-Counter.card, .swiflow-Counter .card {"))
    }

    @Test("class selector with combinator keeps dual emit on the leading class only")
    func classSelectorWithCombinator() {
        let sheet = css { rule(".card .count") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.contains(".swiflow-Counter.card .count, .swiflow-Counter .card .count {"))
    }

    @Test("class-pseudo selector preserves dual emit")
    func classPseudoDualSelector() {
        let sheet = css { rule(".card:hover") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.contains(".swiflow-Counter.card:hover, .swiflow-Counter .card:hover {"))
    }

    @Test("comma-separated selector list scopes EVERY part (audit: unscoped-leak fix)")
    func commaListAllPartsScoped() {
        let sheet = css { rule(".wmo-label, .range") { margin("0") } }
        let result = sheet.cssString(scopeClass: "swiflow-C")
        #expect(result.contains(
            ".swiflow-C.wmo-label, .swiflow-C .wmo-label, .swiflow-C.range, .swiflow-C .range {"))
        // The leak: no part may appear unscoped.
        #expect(!result.contains("\n.range"))
        #expect(!result.contains(", .range,"))
    }

    @Test("comma list mixes class and element parts correctly")
    func commaListMixedParts() {
        let sheet = css { rule("h2, .title") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-C")
        #expect(result.contains(".swiflow-C h2, .swiflow-C.title, .swiflow-C .title {"))
    }

    @Test("commas inside :is(...) do not split")
    func functionalPseudoCommaNotSplit() {
        let sheet = css { rule(":is(.a, .b) span") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-C")
        #expect(result.contains(".swiflow-C :is(.a, .b) span {"))
    }

    @Test("commas inside quoted attribute values do not split")
    func quotedAttrCommaNotSplit() {
        let sheet = css { rule("[data-x=\"a,b\"]") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-C")
        #expect(result.contains(".swiflow-C [data-x=\"a,b\"] {"))
    }

    @Test("unscopeable parts in a comma list stay verbatim while class parts scope")
    func commaListRootStaysVerbatim() {
        let sheet = css { rule(":root, .theme") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-C")
        #expect(result.contains(":root, .swiflow-C.theme, .swiflow-C .theme {"))
    }

    @Test("non-class leading selector unchanged (descendant only)")
    func nonClassLeadingUnchanged() {
        let sheet = css { rule("button") { color("red") } }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.contains(".swiflow-Counter button {"))
        #expect(!result.contains(".swiflow-Counterbutton"))
    }

    @Test("host { } emits scope-class-only selector")
    func hostEntry() {
        let sheet = css {
            host { padding("1rem"); display("flex") }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Toast")
        #expect(result.contains(".swiflow-Toast {"))
        #expect(result.contains("padding: 1rem;"))
        #expect(result.contains("display: flex;"))
        // Must NOT emit a descendant form.
        #expect(!result.contains(".swiflow-Toast .swiflow-Toast"))
    }

    @Test("raw(...) emits string verbatim with no scoping")
    func rawEntry() {
        let sheet = css {
            raw("@property --accent { syntax: \"<color>\"; inherits: true; initial-value: oklch(.6 .15 250); }")
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("@property --accent {"))
        #expect(!result.contains("swiflow-T"))
    }

    @Test("container(...) wraps nested rules in @container and scopes them")
    func containerScopesNestedRules() {
        let sheet = css {
            container("(max-width: 380px)") {
                rule(".actions") { flexDirection("column") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.hasPrefix("@container (max-width: 380px) {"))
        // Nested rule is scoped via the normal dual-selector path — no
        // hand-pasted scope class required.
        #expect(result.contains(".swiflow-Counter.actions, .swiflow-Counter .actions {"))
        #expect(result.contains("flex-direction: column;"))
        #expect(result.hasSuffix("}"))
    }

    @Test("media(...) wraps nested rules in @media and scopes them")
    func mediaScopesNestedRules() {
        let sheet = css {
            media("(max-width: 600px)") {
                rule(".card") { padding("1rem") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.hasPrefix("@media (max-width: 600px) {"))
        #expect(result.contains(".swiflow-Counter.card, .swiflow-Counter .card {"))
    }

    @Test("group nested entries are indented one level")
    func groupIndentsNestedEntries() {
        let sheet = css {
            container("(max-width: 380px)") {
                rule(".x") { color("red") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        // The nested selector line is indented two spaces beneath the at-rule.
        #expect(result.contains("\n  .swiflow-T.x, .swiflow-T .x {"))
        // Declarations are indented a further level (4 spaces total).
        #expect(result.contains("\n    color: red;"))
    }

    @Test("startingStyle(...) wraps nested rules in @starting-style and scopes them")
    func startingStyleScopesNestedRules() {
        let sheet = css {
            startingStyle {
                rule(".signin-dialog[open]") { opacity("0") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Counter")
        #expect(result.hasPrefix("@starting-style {"))
        #expect(result.contains(".swiflow-Counter.signin-dialog[open], .swiflow-Counter .signin-dialog[open] {"))
        #expect(result.contains("opacity: 0;"))
    }

    @Test("outline / outlineOffset emit typed declarations")
    func outlineHelpers() {
        let sheet = css {
            rule("button:focus-visible") {
                outline("2px solid var(--accent)")
                outlineOffset("2px")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("outline: 2px solid var(--accent);"))
        #expect(result.contains("outline-offset: 2px;"))
    }

    @Test("CSSSheet + concatenates entries in order")
    func sheetPlusConcatenates() {
        let a = css { rule(".a") { color("red") } }
        let b = css { rule(".b") { color("blue") } }
        let combined = a + b
        let result = combined.cssString(scopeClass: "swiflow-T")
        let aIdx = result.range(of: ".a")?.lowerBound
        let bIdx = result.range(of: ".b")?.lowerBound
        #expect(aIdx != nil && bIdx != nil)
        #expect(aIdx! < bIdx!)
    }

    @Test("scopedBlock wraps its body in the scope class for native nesting")
    func scopedBlockWrapped() {
        let sheet = CSSSheet(entries: [.scopedBlock(".row {\n  display: grid;\n}")])
        let result = sheet.cssString(scopeClass: "swiflow-Quakes")
        #expect(result == ".swiflow-Quakes {\n  .row {\n    display: grid;\n  }\n}")
    }

    @Test("scopedBlock preserves blank lines without adding trailing spaces")
    func scopedBlockBlankLines() {
        let sheet = CSSSheet(entries: [.scopedBlock(".a { color: red; }\n\n.b { margin: 0; }")])
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result == ".swiflow-T {\n  .a { color: red; }\n\n  .b { margin: 0; }\n}")
    }

    @Test("scopedBlock composes with DSL-built sheets via +")
    func scopedBlockComposes() {
        let sheet = CSSSheet(entries: [.scopedBlock(".a { color: red; }")])
            + css { rule(".b") { margin("0") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains(".swiflow-T {\n  .a { color: red; }\n}"))
        #expect(result.contains(".swiflow-T .b {"))
    }
}
