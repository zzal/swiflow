import Testing
import Foundation
@testable import SwiflowColor
@testable import SwiflowUI

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
    // These tests prove BOTH renderings of the palette: the sRGB base region
    // (hex literals) AND the `@media (color-gamut: p3)` re-pointing. The two
    // must be tested separately because OKLCH perceptual lightness is NOT
    // WCAG relative luminance — a chroma-widened hue at the same L/H has a
    // DIFFERENT photometric Y, so the derived -strong/tints shift contrast
    // on wide-gamut displays (audit V Wave-2 #1; an earlier comment here
    // claimed the opposite and skipped P3 — that claim is now test-pinned
    // false in SwiflowColor's P3WideningTests).
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    private static let hues = [("--sw-accent-strong", "--sw-accent"),
                               ("--sw-danger-strong", "--sw-danger"),
                               ("--sw-success-strong", "--sw-success")]

    /// Rebuild tint = color-mix(in oklab, hue 15%, surface); text = oklch(from hue, L);
    /// return their WCAG contrast.
    private func tintContrast(hueHex: String, surfaceHex: String, textL: Double) -> Double {
        let tint = Color.mixOKLab(Color.hex(hueHex), Color.hex(surfaceHex), weightBase: 0.15)
        return Color.wcagContrast(Color.oklchFrom(Color.hex(hueHex), lightness: textL), tint)
    }

    @Test("Soft-tint -strong text clears WCAG 4.5 on the 15% tint (light & dark)")
    func softTintMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let surface = CSSValueParsing.lightDarkHex(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let hueHex = CSSValueParsing.lightDarkHex(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(base, strong)!
            #expect(tintContrast(hueHex: hueHex.light, surfaceHex: surface.light, textL: L.light) >= 4.5,
                    "\(strong) light fails AA")
            #expect(tintContrast(hueHex: hueHex.dark, surfaceHex: surface.dark, textL: L.dark) >= 4.5,
                    "\(strong) dark fails AA")
        }
    }

    @Test("Under prefers-contrast: more, -strong clears WCAG 7 on the 15% tint")
    func softTintMeetsAAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let more = CSSValueParsing.contrastMoreRegion(sheet)
        let surface = CSSValueParsing.lightDarkHex(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let hueHex = CSSValueParsing.lightDarkHex(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(more, strong)!
            #expect(tintContrast(hueHex: hueHex.light, surfaceHex: surface.light, textL: L.light) >= 7.0,
                    "\(strong) light fails AAA under more-contrast")
            #expect(tintContrast(hueHex: hueHex.dark, surfaceHex: surface.dark, textL: L.dark) >= 7.0,
                    "\(strong) dark fails AAA under more-contrast")
        }
    }

    @Test("Solid-fill accent AND danger text clear WCAG 4.5 (contrast-color result AND fallback)")
    func solidFillMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        // (fill, its -text token) pairs — Button .primary and .danger solid fills.
        for (fillToken, textToken) in [("--sw-accent", "--sw-accent-text"),
                                       ("--sw-danger", "--sw-danger-text")] {
            let fill = CSSValueParsing.lightDarkHex(base, fillToken)!
            let fallback = CSSValueParsing.lightDarkHex(base, textToken)!
            for (fillHex, fallbackHex) in [(fill.light, fallback.light), (fill.dark, fallback.dark)] {
                let bg = Color.hex(fillHex)
                let derived = Color.contrastColor(against: bg)        // what the browser renders
                #expect(Color.wcagContrast(derived, bg) >= 4.5, "contrast-color on \(fillHex) fails AA")
                #expect(Color.wcagContrast(Color.hex(fallbackHex), bg) >= 4.5,
                        "fallback \(fallbackHex) on \(fillHex) fails AA")
            }
            #expect(base.contains("contrast-color(var(\(fillToken)))"), "dynamic \(textToken) declaration missing")
        }
    }

    @Test("P3 block: the widened hues keep the whole derived family at its bars")
    func p3BlockMeetsBars() {
        let p3 = CSSValueParsing.p3Region(sheet)
        let base = CSSValueParsing.baseRegion(sheet)
        let more = CSSValueParsing.contrastMoreRegion(sheet)
        let surface = CSSValueParsing.lightDarkHex(base, "--sw-surface")!

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
            guard let pair = CSSValueParsing.lightDarkP3(p3, fam.hue) else {
                Issue.record("\(fam.hue) missing from the P3 block"); continue
            }
            let lAA = CSSValueParsing.oklchLightnesses(base, fam.strong)!
            let lAAA = CSSValueParsing.oklchLightnesses(more, fam.strong)!
            let arms: [(String, (Double, Double, Double), String, Double, Double)] = [
                ("light", pair.light, surface.light, lAA.light, lAAA.light),
                ("dark", pair.dark, surface.dark, lAA.dark, lAAA.dark),
            ]
            for (mode, triple, surfaceHex, la, laaa) in arms {
                // color(display-p3 r g b) components are gamma-encoded; decode,
                // then express in (extended) linear sRGB — Y stays valid out of gamut.
                let seed = Color.linP3ToLinRGB(LinRGB(
                    r: Color.gammaToLinear(triple.0),
                    g: Color.gammaToLinear(triple.1),
                    b: Color.gammaToLinear(triple.2)))
                let surf = Color.hex(surfaceHex)
                let r = Color.familyRatios(seed: seed, surface: surf, lAA: la, lAAA: laaa, gamut: .p3)
                #expect(r.raw >= fam.rawBar, "\(fam.hue) \(mode) (P3) raw \(r.raw) < \(fam.rawBar)")
                #expect(r.strongAA >= 4.5, "\(fam.strong) \(mode) (P3) \(r.strongAA) < 4.5")
                #expect(r.strongAAA >= 7.0, "\(fam.strong) \(mode) (P3, more-contrast) \(r.strongAAA) < 7")
                if let textToken = fam.textToken {
                    #expect(r.text >= 4.5, "\(textToken) \(mode) (P3, contrast-color) \(r.text) < 4.5")
                    // A browser can support color(display-p3) without
                    // contrast-color — then the STATIC -text fallback renders
                    // on the WIDENED fill; it must clear the bar too.
                    let fallback = CSSValueParsing.lightDarkHex(base, textToken)!
                    let fb = Color.hex(mode == "light" ? fallback.light : fallback.dark)
                    #expect(Color.wcagContrast(fb, seed) >= 4.5,
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
