import Testing
import Foundation
@testable import SwiflowUI

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
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

    @Test("Solid-fill accent text clears WCAG 4.5 (contrast-color result AND fallback)")
    func solidFillMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let accent = CSSValueParsing.lightDarkHex(base, "--sw-accent")!
        let fallback = CSSValueParsing.lightDarkHex(base, "--sw-accent-text")!
        for (accentHex, fallbackHex) in [(accent.light, fallback.light), (accent.dark, fallback.dark)] {
            let bg = Color.hex(accentHex)
            let derived = Color.contrastColor(against: bg)        // what the browser renders
            #expect(Color.wcagContrast(derived, bg) >= 4.5, "contrast-color on \(accentHex) fails AA")
            #expect(Color.wcagContrast(Color.hex(fallbackHex), bg) >= 4.5, "fallback \(fallbackHex) on \(accentHex) fails AA")
        }
        #expect(base.contains("contrast-color(var(--sw-accent))"), "dynamic declaration missing")
    }
}
