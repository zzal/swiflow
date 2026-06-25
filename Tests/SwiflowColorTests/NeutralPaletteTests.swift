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

    @Test("neutralContrastMore overrides text/text-muted/border at higher contrast")
    func moreContrast() {
        let m = Color.neutralContrastMore(accentHex: "#7c3aed")
        #expect(m.map(\.name) == ["--sw-text", "--sw-text-muted", "--sw-border"])
        let baseText = Color.neutralPalette(accentHex: "#7c3aed").first { $0.name == "--sw-text" }!
        let moreText = m.first { $0.name == "--sw-text" }!
        #expect(Color.hex(moreText.light).luminance <= Color.hex(baseText.light).luminance)
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
}
