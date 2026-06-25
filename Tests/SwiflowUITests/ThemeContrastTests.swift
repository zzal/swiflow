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
}
