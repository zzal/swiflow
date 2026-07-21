import Testing
import Foundation
@testable import SwiflowColor
@testable import SwiflowUI

// This suite drives the SwiflowColor math enum (`Color.hex/mixOKLab/wcagContrast/…`).
// SwiflowUI now also exports a public `Color` value type, so pin bare `Color` here.
private typealias Color = SwiflowColor.Color

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
    // These tests prove BOTH renderings of the palette from the SAME oklch primary
    // tokens: the sRGB rendering (the widened seed gamut-clamped) AND the P3 rendering
    // (the widened seed itself). They must be checked separately because OKLCH perceptual
    // lightness is NOT WCAG relative luminance — a chroma-widened hue at the same L/H has
    // a DIFFERENT photometric Y, so the derived -strong/tints shift contrast on wide-gamut
    // displays (test-pinned false in SwiflowColor's P3WideningTests). Primary tokens are
    // resolved via CSSValueParsing.lightDarkColor (oklch()→LinRGB, unclamped).
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    private static let hues = [("--sw-accent-strong", "--sw-accent"),
                               ("--sw-danger-strong", "--sw-danger"),
                               ("--sw-success-strong", "--sw-success")]

    /// Rebuild tint = color-mix(in oklab, hue 15%, surface); text = oklch(from hue, L);
    /// return their WCAG contrast. Seeds are LinRGB (already clamped to the target gamut).
    private func tintContrast(hue: LinRGB, surface: LinRGB, textL: Double) -> Double {
        let tint = Color.mixOKLab(hue, surface, weightBase: 0.15)
        return Color.wcagContrast(Color.oklchFrom(hue, lightness: textL), tint)
    }

    @Test("Soft-tint -strong text clears WCAG 4.5 on the 15% tint (light & dark)")
    func softTintMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let surface = CSSValueParsing.lightDarkColor(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let h = CSSValueParsing.lightDarkColor(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(base, strong)!
            #expect(tintContrast(hue: Color.clampGamut(h.light), surface: Color.clampGamut(surface.light), textL: L.light) >= 4.5,
                    "\(strong) light fails AA")
            #expect(tintContrast(hue: Color.clampGamut(h.dark), surface: Color.clampGamut(surface.dark), textL: L.dark) >= 4.5,
                    "\(strong) dark fails AA")
        }
    }

    @Test("Under prefers-contrast: more, -strong clears WCAG 7 on the 15% tint")
    func softTintMeetsAAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let more = CSSValueParsing.contrastMoreRegion(sheet)
        let surface = CSSValueParsing.lightDarkColor(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let h = CSSValueParsing.lightDarkColor(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(more, strong)!
            #expect(tintContrast(hue: Color.clampGamut(h.light), surface: Color.clampGamut(surface.light), textL: L.light) >= 7.0,
                    "\(strong) light fails AAA under more-contrast")
            #expect(tintContrast(hue: Color.clampGamut(h.dark), surface: Color.clampGamut(surface.dark), textL: L.dark) >= 7.0,
                    "\(strong) dark fails AAA under more-contrast")
        }
    }

    @Test("Solid-fill accent AND danger text clear WCAG 4.5 (contrast-color result AND fallback)")
    func solidFillMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        // (fill, its -text token) pairs — Button .primary and .danger solid fills.
        for (fillToken, textToken) in [("--sw-accent", "--sw-accent-text"),
                                       ("--sw-danger", "--sw-danger-text")] {
            let fill = CSSValueParsing.lightDarkColor(base, fillToken)!   // oklch primary
            let fallback = CSSValueParsing.lightDarkHex(base, textToken)! // -text fallback stays hex
            for (fillC, fallbackHex) in [(fill.light, fallback.light), (fill.dark, fallback.dark)] {
                let bg = Color.clampGamut(fillC)                      // the sRGB-rendered fill
                let derived = Color.contrastColor(against: bg)        // what the browser renders
                #expect(Color.wcagContrast(derived, bg) >= 4.5, "contrast-color on \(fillToken) fails AA")
                #expect(Color.wcagContrast(Color.hex(fallbackHex), bg) >= 4.5,
                        "fallback \(fallbackHex) on \(fillToken) fails AA")
            }
            #expect(base.contains("contrast-color(var(\(fillToken)))"), "dynamic \(textToken) declaration missing")
        }
    }

    @Test("On a P3 display the widened oklch primaries keep the whole derived family at its bars")
    func oklchPrimariesMeetBarsOnP3() {
        let base = CSSValueParsing.baseRegion(sheet)
        let more = CSSValueParsing.contrastMoreRegion(sheet)
        let surface = CSSValueParsing.lightDarkColor(base, "--sw-surface")!

        // (hue token, its -strong, raw-on-surface bar, -text token when a solid
        // fill exists). Mirrors the sRGB coverage: accent as text/links 3:1,
        // danger as error text 4.5, success/warning as non-text UI 3:1.
        let families: [(hue: String, strong: String, rawBar: Double, textToken: String?)] = [
            ("--sw-accent", "--sw-accent-strong", 3.0, "--sw-accent-text"),
            ("--sw-danger", "--sw-danger-strong", 4.5, "--sw-danger-text"),
            ("--sw-success", "--sw-success-strong", 3.0, nil),
            ("--sw-warning", "--sw-warning-strong", 3.0, nil),
        ]
        for fam in families {
            let seed = CSSValueParsing.lightDarkColor(base, fam.hue)!   // UNCLAMPED widened oklch
            let lAA = CSSValueParsing.oklchLightnesses(base, fam.strong)!
            let lAAA = CSSValueParsing.oklchLightnesses(more, fam.strong)!
            let arms: [(String, LinRGB, LinRGB, Double, Double)] = [
                ("light", seed.light, surface.light, lAA.light, lAAA.light),
                ("dark", seed.dark, surface.dark, lAA.dark, lAAA.dark),
            ]
            for (mode, seedC, surf, la, laaa) in arms {
                // The unclamped oklch seed IS what a P3 display renders (extended linear
                // sRGB; Y stays valid out of the sRGB gamut). Surfaces are neutral/in-gamut.
                let r = Color.familyRatios(seed: seedC, surface: Color.clampGamut(surf), lAA: la, lAAA: laaa, gamut: .p3)
                #expect(r.raw >= fam.rawBar, "\(fam.hue) \(mode) (P3) raw \(r.raw) < \(fam.rawBar)")
                #expect(r.strongAA >= 4.5, "\(fam.strong) \(mode) (P3) \(r.strongAA) < 4.5")
                #expect(r.strongAAA >= 7.0, "\(fam.strong) \(mode) (P3, more-contrast) \(r.strongAAA) < 7")
                if let textToken = fam.textToken {
                    #expect(r.text >= 4.5, "\(textToken) \(mode) (P3, contrast-color) \(r.text) < 4.5")
                    // A browser can render the widened oklch without contrast-color()
                    // support — then the STATIC -text fallback renders on the widened
                    // fill; it must clear the bar too.
                    let fallback = CSSValueParsing.lightDarkHex(base, textToken)!
                    let fb = Color.hex(mode == "light" ? fallback.light : fallback.dark)
                    #expect(Color.wcagContrast(fb, seedC) >= 4.5,
                            "\(textToken) \(mode) static fallback on the P3 fill < 4.5")
                }
            }
        }
    }

    @Test("Danger hover/active derive from --sw-danger exactly like the accent family")
    func dangerFamilyDerives() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(base.contains("--sw-danger-hover: light-dark(oklch(from var(--sw-danger) calc(l - 0.08) c h)"),
                "hover derivation missing — re-pointing --sw-danger must cascade the family")
        #expect(base.contains("--sw-danger-active: light-dark(oklch(from var(--sw-danger) calc(l - 0.16) c h)"),
                "active derivation missing")
    }
}
