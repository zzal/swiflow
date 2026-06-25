import Testing
import Foundation
@testable import SwiflowColor

@Suite("AccentTheme")
struct AccentThemeTests {
    @Test("A good brand color validates clean and emits a light-dark --sw-accent")
    func goodSeedEmitsCSS() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
        #expect(css.contains(":root"))
    }

    @Test("3-digit hex (#rgb) and missing # are normalized")
    func normalizesHex() throws {
        // 6-char without the leading #
        let css6 = try Color.accentThemeCSS(primaryHex: "3b82f6")
        #expect(css6.contains("--sw-accent: light-dark(#3b82f6,"))
        // 3-digit shorthand expands to #rrggbb
        let css3 = try Color.accentThemeCSS(primaryHex: "#06f")
        #expect(css3.contains("--sw-accent: light-dark(#0066ff,"))
    }

    @Test("A medium-dark accent passes (the legacy -text fallback is not gated)")
    func mediumDarkAccentPasses() throws {
        // #7c3aed (violet) fails only the pre-Baseline dark-text fallback; the Baseline
        // contrast-color() path flips to white and is AA, so it must validate clean.
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed")
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(Color.validateAccentFamily(lightAccentHex: "#7c3aed",
                                            darkAccentHex: Color.darkAccent(from: "#7c3aed")).isEmpty)
    }

    @Test("A washed-out seed fails validation with a specific diagnostic")
    func badSeedThrows() {
        // A light yellow: ~1.07:1 as accent text/links on white — below the 3:1 UI bar.
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#fde047")
        }
    }

    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }

    @Test("validateAccentFamily returns failures naming token + mode")
    func validationNamesFailures() {
        let fails = Color.validateAccentFamily(lightAccentHex: "#fde047",
                                               darkAccentHex: Color.darkAccent(from: "#fde047"))
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("as text") })
        #expect(fails.allSatisfy { !$0.token.isEmpty && $0.ratio < $0.target })
    }

    @Test("includeNeutrals: false is byte-for-byte the accent-only output (no neutral tokens)")
    func accentOnlyUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", includeNeutrals: false)
        #expect(a == b)
        #expect(!a.contains("--sw-surface"))
        #expect(!a.contains("@media"))
    }

    @Test("includeNeutrals: true emits the neutral ramp and a prefers-contrast block")
    func fullPaletteEmitted() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("--sw-text: light-dark(#"))
        #expect(css.contains("--sw-border: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("--neutrals"))   // header mentions the flag
    }
}
