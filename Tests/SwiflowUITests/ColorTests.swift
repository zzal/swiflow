import Testing
import Swiflow
@testable import SwiflowUI

/// Knob C: the typed OKLCH `Color` value. A pure CSS-string formatter (no color
/// math, no SwiflowColor dependency), plus its `ThemeToken` overloads.
@Suite("Color")
struct ColorValueTests {
    @Test("oklch renders space-separated, integral parts without a decimal point")
    func oklchFormatting() {
        #expect(Color.oklch(l: 0.62, c: 0.17, h: 255).css == "oklch(0.62 0.17 255)")
        #expect(Color.oklch(l: 1, c: 0, h: 0).css == "oklch(1 0 0)")
        #expect(Color.oklch(l: 0.5, c: 0, h: 120).css == "oklch(0.5 0 120)")
    }

    @Test("alpha is emitted only when below 1")
    func oklchAlpha() {
        #expect(Color.oklch(l: 0.62, c: 0.17, h: 255, alpha: 1).css == "oklch(0.62 0.17 255)")
        #expect(Color.oklch(l: 0.62, c: 0.17, h: 255, alpha: 0.5).css == "oklch(0.62 0.17 255 / 0.5)")
    }

    @Test("hex and raw string literals pass through verbatim")
    func escapeHatches() {
        #expect(Color.hex("#1a1a1a").css == "#1a1a1a")
        #expect(Color("var(--brand)").css == "var(--brand)")
        let literal: Color = "oklch(0.7 0.1 20)"
        #expect(literal.css == "oklch(0.7 0.1 20)")
    }
}

@Suite("ThemeToken+Color")
@MainActor
struct ThemeTokenColorTests {
    // Mirrors ThemeScopeTests' helper.
    private func styleOf(_ node: VNode) -> [String: String] {
        guard case .element(let data) = node else { return [:] }
        return data.style
    }

    @Test("branded Color overloads set the token to the rendered css value")
    func brandedOverloads() {
        #expect(ThemeToken.accent(.oklch(l: 0.62, c: 0.17, h: 255))
            == ThemeToken(name: "--sw-accent", value: "oklch(0.62 0.17 255)"))
        #expect(ThemeToken.surface(.oklch(l: 1, c: 0, h: 0)).value == "oklch(1 0 0)")
        #expect(ThemeToken.danger(.hex("#dc2626")).value == "#dc2626")
    }

    @Test("set(_:_ Color:) and token(_:_ Color:) render css")
    func setAndTokenOverloads() {
        #expect(ThemeToken.set(.warning, .oklch(l: 0.7, c: 0.16, h: 70))
            == ThemeToken(name: "--sw-warning", value: "oklch(0.7 0.16 70)"))
        #expect(ThemeToken.token("--brand-x", .oklch(l: 0.5, c: 0.1, h: 200)).value == "oklch(0.5 0.1 200)")
    }

    @Test("Theme(.accent(Color)) still re-derives the accent family")
    func accentColorReDerives() {
        let s = styleOf(Theme(.accent(.oklch(l: 0.62, c: 0.17, h: 255))) { text("x") })
        #expect(s["--sw-accent"] == "oklch(0.62 0.17 255)")
        #expect(s["--sw-focus-ring"] == "var(--sw-accent)")
        #expect(s["--sw-accent-hover"]?.contains("oklch(from var(--sw-accent)") == true)
    }
}
