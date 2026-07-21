import Testing
import Foundation
@testable import SwiflowColor

/// Knob A: the OKLCH-primary input door (`Color.parseColor` / `normalizeColor`).
/// The engine already runs in OKLCH internally; these pin that an `oklch()` seed
/// is accepted, canonicalized to sRGB hex (the emitted fallback + validation anchor),
/// and drives the generator identically to its hex equivalent.
@Suite("OKLCHInput")
struct OKLCHInputTests {
    @Test("oklch achromatic extremes normalize to exact hex")
    func achromaticExtremes() throws {
        #expect(try Color.normalizeColor("oklch(0 0 0)") == "#000000")
        #expect(try Color.normalizeColor("oklch(1 0 0)") == "#ffffff")
        #expect(try Color.normalizeColor("oklch(100% 0 0)") == "#ffffff")   // percentage L
    }

    @Test("alpha / deg / whitespace / case variants parse (alpha dropped, deg stripped)")
    func toleratedForms() throws {
        #expect(try Color.normalizeColor("oklch(1 0 0 / 0.5)") == "#ffffff")   // alpha ignored
        #expect(try Color.normalizeColor("oklch(1 0 0deg)") == "#ffffff")      // deg suffix
        #expect(try Color.normalizeColor("  oklch(1 0 0)  ") == "#ffffff")     // outer whitespace
        #expect(try Color.normalizeColor("OKLCH(1 0 0)") == "#ffffff")         // case-insensitive fn
    }

    @Test("hex still normalizes unchanged through the color door")
    func hexPassThrough() throws {
        #expect(try Color.normalizeColor("#3b82f6") == "#3b82f6")
        #expect(try Color.normalizeColor("#06f") == "#0066ff")
    }

    @Test("an oklch seed derived from a hex round-trips to that hex")
    func roundTripFromHex() throws {
        let hex = "#3b82f6"
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(hex)))
        var deg = lch.H * 180 / .pi
        if deg < 0 { deg += 360 }
        let oklch = "oklch(\(lch.L) \(lch.C) \(deg))"
        #expect(try Color.normalizeColor(oklch) == hex)
    }

    @Test("malformed oklch throws invalidColor")
    func malformedThrows() {
        for bad in ["oklch(nope)", "oklch(1 0)", "oklch(1 0 0 0)", "oklch(1 0 0", "oklch()"] {
            #expect(throws: ThemeError.self) { _ = try Color.normalizeColor(bad) }
        }
    }

    @Test("generator accepts an oklch primary seed and emits a valid accent block")
    func generatorAcceptsOklch() throws {
        let r = try Color.accentThemeCSS(primaryHex: "oklch(0.62 0.17 255)")
        #expect(r.css.contains(":root"))
        #expect(r.css.contains("--sw-accent: light-dark(#"))         // hex net still emitted
        #expect(r.css.contains("--sw-accent: light-dark(oklch("))    // + progressive oklch line
    }

    @Test("an oklch primary produces the same CSS as its normalized hex")
    func generatorOklchMatchesHex() throws {
        let oklch = "oklch(0.62 0.17 255)"
        let hex = try Color.normalizeColor(oklch)
        let fromOklch = try Color.accentThemeCSS(primaryHex: oklch).css
        let fromHex = try Color.accentThemeCSS(primaryHex: hex).css
        #expect(fromOklch == fromHex)   // oklch collapses to the canonical hex seed, then derives identically
    }
}
