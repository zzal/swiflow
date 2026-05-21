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
}
