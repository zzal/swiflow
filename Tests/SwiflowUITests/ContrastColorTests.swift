import Testing
import Foundation
import SwiflowColor
@testable import SwiflowUI

@Suite("ContrastColor")
struct ContrastColorTests {
    @Test("Hex parses to linear sRGB with correct WCAG luminance")
    func luminanceEndpoints() {
        #expect(abs(Color.hex("#ffffff").luminance - 1.0) < 1e-9)
        #expect(abs(Color.hex("#000000").luminance - 0.0) < 1e-9)
    }

    @Test("WCAG contrast: white on black is 21:1; #767676 on white is ~4.54:1")
    func wcagKnownPairs() {
        #expect(abs(Color.wcagContrast(.white, .black) - 21.0) < 0.01)
        let midGrayOnWhite = Color.wcagContrast(Color.hex("#767676"), .white)
        #expect(abs(midGrayOnWhite - 4.54) < 0.05)
    }

    @Test("OKLab round-trips linear sRGB within tolerance")
    func okLabRoundTrip() {
        for hex in ["#3b82f6", "#dc2626", "#16a34a", "#1a1a1a", "#f6f7f9"] {
            let c = Color.hex(hex)
            let back = Color.okLabToLinRGB(Color.linRGBToOKLab(c))
            #expect(abs(back.r - c.r) < 1e-6)
            #expect(abs(back.g - c.g) < 1e-6)
            #expect(abs(back.b - c.b) < 1e-6)
        }
    }

    @Test("color-mix(in oklab) endpoints and identity")
    func mixOKLab() {
        // Mixing a color with itself returns the same color.
        let blue = Color.hex("#3b82f6")
        let same = Color.mixOKLab(blue, blue, weightBase: 0.15)
        #expect(abs(same.luminance - blue.luminance) < 1e-8)
        // weightBase 1.0 → all base; 0.0 → all other.
        #expect(Color.mixOKLab(.white, .black, weightBase: 1.0).luminance > 0.99)
        #expect(Color.mixOKLab(.white, .black, weightBase: 0.0).luminance < 0.01)
    }

    @Test("oklch(from …) keeps hue, replaces lightness")
    func oklchFrom() {
        let out = Color.oklchFrom(Color.hex("#3b82f6"), lightness: 0.40)
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(out))
        #expect(abs(lch.L - 0.40) < 0.02)   // clamp may nudge slightly
    }

    @Test("contrast-color picks the higher-contrast of black/white")
    func contrastColor() {
        #expect(Color.contrastColor(against: .white) == .black)
        #expect(Color.contrastColor(against: .black) == .white)
        // Default light accent #3b82f6 → black wins (5.7:1 vs white 3.68:1).
        #expect(Color.contrastColor(against: Color.hex("#3b82f6")) == .black)
    }
}

@Suite("CSSValueParsing")
@MainActor
struct CSSValueParsingTests {
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    @Test("baseRegion stops before the first media layer")
    func baseRegionSplit() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(base.contains("--sw-accent"))
        #expect(!base.contains("@media"))
    }

    @Test("lightDarkHex reads the current accent/surface/accent-text literals")
    func lightDarkHexReads() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(CSSValueParsing.lightDarkHex(base, "--sw-accent")!  == ("#3b82f6", "#60a5fa"))
        #expect(CSSValueParsing.lightDarkHex(base, "--sw-surface")! == ("#ffffff", "#1a1a1a"))
    }

    @Test("contrastMoreRegion isolates the prefers-contrast block")
    func contrastMoreRegionReads() {
        let region = CSSValueParsing.contrastMoreRegion(sheet)
        #expect(region.contains("--sw-border-width: 2px"))
        #expect(!region.contains("color-gamut"))   // a different layer
    }

    @Test("oklchLightnesses parses an L pair from a sample declaration")
    func oklchLightnessesParses() {
        let sample = "--sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.40 c h), oklch(from var(--sw-accent) 0.80 c h));"
        let L = CSSValueParsing.oklchLightnesses(sample, "--sw-accent-strong")!
        #expect(abs(L.light - 0.40) < 1e-9)
        #expect(abs(L.dark - 0.80) < 1e-9)
    }
}
