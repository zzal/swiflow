import Testing
import Foundation
@testable import SwiflowColor

/// The widened `oklch()` line the generator emits after the hex fallback WINS on every
/// oklch-capable engine — including an sRGB display, which gamut-maps the widened value
/// into sRGB. Chroma-widening at constant L/H shifts WCAG luminance, so the widened color
/// must clear the whole derived family's bars in BOTH gamut interpretations, not just P3.
/// These pin that contract (the sRGB arm is the gap this closes).
@Suite("P3WidenBothGamuts")
struct P3WidenBothGamutsTests {
    // The shipped contract familyPasses is measured against (mirrors Theme.swift / Color's
    // private constants — kept literal here the same way ThemeContrastTests does).
    static let surfaceLight = Color.hex("#ffffff"), surfaceDark = Color.hex("#1a1a1a")
    static let strongL = (lightAA: 0.40, darkAA: 0.80, lightAAA: 0.30, darkAAA: 0.88)

    /// Pull `token: light-dark(oklch(…), oklch(…));` back out of the emitted CSS → (lightLin, darkLin).
    private func widenedArms(_ css: String, _ token: String) -> (light: LinRGB, dark: LinRGB)? {
        let t = NSRegularExpression.escapedPattern(for: token)
        let pattern = "\(t): light-dark\\((oklch\\([^)]*\\)), (oklch\\([^)]*\\))\\)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)),
              let lr = Range(m.range(at: 1), in: css), let dr = Range(m.range(at: 2), in: css),
              let light = try? Color.parseColor(String(css[lr])),
              let dark = try? Color.parseColor(String(css[dr])) else { return nil }
        return (light, dark)
    }

    @Test("the widened accent oklch clears the family bars in BOTH sRGB and P3 (light & dark)")
    func accentWidenedPassesBothGamuts() throws {
        // Saturated seeds → the largest P3 widening → the most likely to expose an sRGB-only
        // shortfall the P3-only check would have missed.
        for seed in ["#3b82f6", "#7c3aed", "oklch(0.62 0.20 150)", "oklch(0.55 0.24 27)"] {
            let css = try Color.accentThemeCSS(primaryHex: seed)
            // A failing seed emits unwidened by design (see the floor test); only clean seeds
            // carry the both-gamuts guarantee.
            guard css.failures.isEmpty else { continue }
            let arms = widenedArms(css.css, "--sw-accent")!
            for (mode, seedC, surface, lAA, lAAA) in [
                ("light", arms.light, Self.surfaceLight, Self.strongL.lightAA, Self.strongL.lightAAA),
                ("dark",  arms.dark,  Self.surfaceDark,  Self.strongL.darkAA,  Self.strongL.darkAAA),
            ] {
                // P3: the widened candidate as a P3 display renders it (unclamped extended-linear).
                #expect(Color.familyPasses(seed: seedC, surface: surface,
                                           lAA: lAA, lAAA: lAAA, rawBar: 3.0, textBar: 4.5, gamut: .p3),
                        "\(seed) \(mode): widened accent fails the P3 family")
                // sRGB: the same value gamut-mapped into sRGB (clamped seed) — the gap this closes.
                #expect(Color.familyPasses(seed: Color.clampGamut(seedC), surface: surface,
                                           lAA: lAA, lAAA: lAAA, rawBar: 3.0, textBar: 4.5, gamut: .srgb),
                        "\(seed) \(mode): widened accent fails the sRGB family (P3-only gap)")
            }
        }
    }

    @Test("a widened danger status oklch also clears both gamuts (the textBar-nil path)")
    func dangerWidenedPassesBothGamuts() throws {
        // Status tokens run the same widen-then-back-off path with textBar nil and a 4.5 raw bar
        // (danger renders as error text). Exercise that branch on a saturated red.
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "oklch(0.58 0.22 27)")
        guard css.failures.isEmpty else { return }
        let arms = widenedArms(css.css, "--sw-danger")!
        for (mode, seedC, surface, lAA, lAAA) in [
            ("light", arms.light, Self.surfaceLight, Self.strongL.lightAA, Self.strongL.lightAAA),
            ("dark",  arms.dark,  Self.surfaceDark,  Self.strongL.darkAA,  Self.strongL.darkAAA),
        ] {
            #expect(Color.familyPasses(seed: seedC, surface: surface,
                                       lAA: lAA, lAAA: lAAA, rawBar: 4.5, textBar: nil, gamut: .p3),
                    "danger \(mode): widened fails the P3 family")
            #expect(Color.familyPasses(seed: Color.clampGamut(seedC), surface: surface,
                                       lAA: lAA, lAAA: lAAA, rawBar: 4.5, textBar: nil, gamut: .srgb),
                    "danger \(mode): widened fails the sRGB family (P3-only gap)")
        }
    }

    @Test("a seed that fails only in sRGB still emits its oklch arm unwidened (the scan floor)")
    func failingSeedEmitsUnwidenedFloor() throws {
        // #fde047 (yellow) can't meet the accent-as-text bar → no widening can satisfy the sRGB
        // arm, so the scan bottoms out at the seed's own chroma. The oklch line must then render
        // the SAME color as the hex fallback (no widening), introducing no new failure.
        let seedHex = try Color.normalizeColor("#fde047")
        let css = try Color.accentThemeCSS(primaryHex: seedHex)
        #expect(!css.failures.isEmpty)                                   // it does fail (as expected)
        let arms = widenedArms(css.css, "--sw-accent")!
        let seedLin = Color.hex(seedHex)
        // light arm == the seed itself (floor: unwidened); dark arm == the derived dark seed.
        #expect(abs(arms.light.luminance - seedLin.luminance) < 0.01,
                "failing seed's oklch light arm should be unwidened (== hex fallback color)")
    }
}
