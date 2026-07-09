// Tests/SwiflowUITests/TokenTests.swift
//
// Audit V Wave-2 #5: the typed token vocabulary. One `Token` type serves
// both sides — reads (`.style("background", .surface)`) and writes
// (ThemeToken routes through the same constants) — so the vocabularies
// cannot drift. The anti-drift sweep below is the trust anchor: every
// Token static must name a token the shipped base sheet actually sets.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@Suite("Token vocabulary")
@MainActor
struct TokenTests {

    @Test("ANTI-DRIFT: every Token names a token the shipped sheet sets (Token ⊆ sheet)")
    func vocabularyMatchesSheet() {
        let sheet = SwiflowUI.baseStyleSheet.cssString(scopeClass: "")
        for token in Token.all {
            #expect(sheet.contains("\(token.name):"),
                    "\(token.name) is not declared in the base sheet — typo in Token, or the sheet dropped it")
        }
    }

    @Test(".css renders the var() reference")
    func cssRendersVar() {
        #expect(Token.surface.css == "var(--sw-surface)")
        #expect(Token.spaceMd.css == "var(--sw-space-md)")
        #expect(Token.dangerText.css == "var(--sw-danger-text)")
    }

    @Test("the typed .style overload emits exactly what the stringly spelling does")
    func styleOverloadIdentical() {
        let typed = elementOf(div(.style("background", Token.surface)))!
        let stringly = elementOf(div(.style("background", "var(--sw-surface)")))!
        #expect(typed.style["background"] == stringly.style["background"])
        #expect(typed.style["background"] == "var(--sw-surface)")
    }

    @Test("the VNode-modifier twin matches too — the demo's chained spelling")
    func modifierOverloadIdentical() {
        let typed = elementOf(div {}.style("background", Token.surface))!
        #expect(typed.style["background"] == "var(--sw-surface)")
    }

    @Test("ThemeToken statics still emit the same names — the Token refactor is invisible")
    func themeTokenNamesUnchanged() {
        #expect(ThemeToken.accent("#000").name == "--sw-accent")
        #expect(ThemeToken.radius("4px").name == "--sw-radius")
        #expect(ThemeToken.surface("#fff").name == "--sw-surface")
        #expect(ThemeToken.text("#111").name == "--sw-text")
        #expect(ThemeToken.border("#eee").name == "--sw-border")
        #expect(ThemeToken.danger("#f00").name == "--sw-danger")
        #expect(ThemeToken.success("#0f0").name == "--sw-success")
    }

    @Test("ThemeToken.set overrides any typed token without a stringly name")
    func themeTokenSet() {
        let t = ThemeToken.set(.warning, "#b45309")
        #expect(t.name == "--sw-warning")
        #expect(t.value == "#b45309")
    }
}

@Suite("Card .plain")
@MainActor
struct CardPlainTests {

    @Test(".plain is the bare padded surface — base class only, no variant CSS")
    func plainVariant() {
        let card = elementOf(Card(variant: .plain) {})!
        #expect(card.attributes["class"] == "sw-card sw-card--plain")
        let css = cardStyleSheet.cssString(scopeClass: "")
        #expect(!css.contains(".sw-card--plain"),
                "the base .sw-card class IS the whole plain look — the variant adds nothing")
    }
}

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@Suite("style value token validation", .serialized)
@MainActor
struct StyleTokenValidationTests {

    private func captureWarnings(_ body: () -> Void) -> [String] {
        installStyleTokenValidator()
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    @Test("a typo'd --sw- token in a stringly .style value warns")
    func typoWarns() {
        let warnings = captureWarnings {
            _ = div(.style("background", "var(--sw-surfce)"))   // the audit's exact typo
        }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("--sw-surfce"))
    }

    @Test("known tokens, composites, and app-custom props stay silent")
    func validSilent() {
        let warnings = captureWarnings {
            _ = div(.style("background", "var(--sw-surface)"))
            _ = div(.style("border", "var(--sw-border-width) solid var(--sw-border)"))
            _ = div(.style("color", "var(--my-app-color)"))     // non --sw-: never checked
            _ = div {}.style("padding", "var(--sw-space-md)")   // the modifier path is hooked too
        }
        #expect(warnings.isEmpty)
    }

    @Test("the modifier path catches typos too")
    func modifierPathWarns() {
        let warnings = captureWarnings {
            _ = div {}.style("gap", "var(--sw-spce-md)")
        }
        #expect(warnings.count == 1)
    }
}
