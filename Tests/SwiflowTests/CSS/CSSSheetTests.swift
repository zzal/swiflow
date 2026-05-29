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

    @Test("cssVar() emits custom property declaration")
    func cssVarDeclaration() {
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
}
