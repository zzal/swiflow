import Testing
import Foundation
@testable import SwiflowColor
@testable import SwiflowUI

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
    // These tests prove the sRGB base palette (the specification contract). The
    // `@media (color-gamut: p3)` block re-points the same hues to display-p3 values,
    // but the `oklch(from …)` text derivation pins the SAME lightnesses regardless of
    // input hue, so p3 is a gamut upgrade of the same perceptual lightness and is
    // intentionally not re-tested here (the parser reads only the #rrggbb sRGB literals).
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

    @Test("Danger hover/active derive from --sw-danger exactly like the accent family")
    func dangerFamilyDerives() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(base.contains("--sw-danger-hover: light-dark(oklch(from var(--sw-danger) calc(l - 0.08) c h)"),
                "hover derivation missing — re-pointing --sw-danger must cascade the family")
        #expect(base.contains("--sw-danger-active: light-dark(oklch(from var(--sw-danger) calc(l - 0.16) c h)"),
                "active derivation missing")
    }
}
