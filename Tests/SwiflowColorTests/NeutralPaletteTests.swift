import Testing
import Foundation
@testable import SwiflowColor

@Suite("NeutralPalette")
struct NeutralPaletteTests {
    @Test("Derives the six tokens in order, well-formed, with the right light/dark direction")
    func sixTokens() {
        let p = Color.neutralPalette(accentHex: "#7c3aed")
        #expect(p.map(\.name) == ["--sw-bg", "--sw-surface", "--sw-surface-2",
                                  "--sw-text", "--sw-text-muted", "--sw-border"])
        for t in p {
            for h in [t.light, t.dark] {
                #expect(h.count == 7 && h.hasPrefix("#"))
            }
        }
        let surface = p.first { $0.name == "--sw-surface" }!
        let text = p.first { $0.name == "--sw-text" }!
        #expect(Color.hex(surface.light).luminance > 0.8)   // light surface is bright
        #expect(Color.hex(text.light).luminance < 0.1)      // light-mode text is dark
        #expect(Color.hex(surface.dark).luminance < 0.1)    // dark surface is dark
        #expect(Color.hex(text.dark).luminance > 0.8)       // dark-mode text is bright
    }

    @Test("Neutrals carry an accent tint (a mid token is not pure gray)")
    func tinted() {
        let border = Color.neutralPalette(accentHex: "#7c3aed").first { $0.name == "--sw-border" }!
        let c = Color.hex(border.light)
        #expect(!(c.r == c.g && c.g == c.b))   // channels differ → tinted, not pure gray
    }

    @Test("neutralContrastMore strengthens text contrast on the surfaces in both modes")
    func moreContrast() {
        let accent = "#7c3aed"
        let base = Color.neutralPalette(accentHex: accent)
        let more = Color.neutralContrastMore(accentHex: accent)
        #expect(more.map(\.name) == ["--sw-text", "--sw-text-muted", "--sw-border"])
        let surface = base.first { $0.name == "--sw-surface" }!
        for token in ["--sw-text", "--sw-text-muted"] {
            let b = base.first { $0.name == token }!
            let m = more.first { $0.name == token }!
            // more-contrast must be a higher WCAG ratio than base against the surface, both modes.
            #expect(Color.wcagContrast(Color.hex(m.light), Color.hex(surface.light))
                  > Color.wcagContrast(Color.hex(b.light), Color.hex(surface.light)),
                    "\(token) light should strengthen under more-contrast")
            #expect(Color.wcagContrast(Color.hex(m.dark), Color.hex(surface.dark))
                  > Color.wcagContrast(Color.hex(b.dark), Color.hex(surface.dark)),
                    "\(token) dark should strengthen under more-contrast")
        }
    }
}

@Suite("ValidateNeutrals")
struct ValidateNeutralsTests {
    @Test("Default-derived neutrals clear AA for normal accents")
    func passesForNormalAccents() {
        for accent in ["#3b82f6", "#7c3aed", "#16a34a", "#dc2626"] {
            let fails = Color.validateNeutrals(Color.neutralPalette(accentHex: accent))
            #expect(fails.isEmpty, "neutrals for \(accent) should be AA, got \(fails)")
        }
    }

    @Test("Text too light against the surface fails with a per-mode diagnostic")
    func failsWhenTextTooLight() {
        // Contrived: light-mode text is near-white on a white surface → ~1:1.
        let bad: [Color.TokenPair] = [
            ("--sw-bg", "#ffffff", "#000000"),
            ("--sw-surface", "#ffffff", "#000000"),
            ("--sw-text", "#eeeeee", "#111111"),
            ("--sw-text-muted", "#dddddd", "#222222"),
        ]
        let fails = Color.validateNeutrals(bad)
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("--sw-text") && $0.mode == "light" })
        #expect(fails.allSatisfy { $0.ratio < $0.target })
    }

    @Test("Incomplete palette short-circuits to no failures (documented guard behavior)")
    func incompletePaletteGuard() {
        // validateNeutrals requires surface/bg/text/text-muted; absent any, it returns [].
        // This is the intentional guard — the production caller (neutralPalette) always supplies
        // all six. Documented so a partial-palette caller knows [] means "couldn't check," not "AA".
        #expect(Color.validateNeutrals([]).isEmpty)
        #expect(Color.validateNeutrals([("--sw-text", "#000", "#fff")]).isEmpty)
    }
}
