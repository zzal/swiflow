import Testing
import Foundation
@testable import SwiflowColor

@Suite("AccentTheme")
struct AccentThemeTests {
    @Test("A good brand color validates clean and emits a light-dark --sw-accent")
    func goodSeedEmitsCSS() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
        #expect(css.contains(":root"))
    }

    @Test("3-digit hex (#rgb) and missing # are normalized")
    func normalizesHex() throws {
        // 6-char without the leading #
        let css6 = try Color.accentThemeCSS(primaryHex: "3b82f6")
        #expect(css6.contains("--sw-accent: light-dark(#3b82f6,"))
        // 3-digit shorthand expands to #rrggbb
        let css3 = try Color.accentThemeCSS(primaryHex: "#06f")
        #expect(css3.contains("--sw-accent: light-dark(#0066ff,"))
    }

    @Test("A medium-dark accent passes (the legacy -text fallback is not gated)")
    func mediumDarkAccentPasses() throws {
        // #7c3aed (violet) fails only the pre-Baseline dark-text fallback; the Baseline
        // contrast-color() path flips to white and is AA, so it must validate clean.
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed")
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(Color.validateAccentFamily(lightAccentHex: "#7c3aed",
                                            darkAccentHex: Color.darkAccent(from: "#7c3aed")).isEmpty)
    }

    @Test("A washed-out seed fails validation with a specific diagnostic")
    func badSeedThrows() {
        // A light yellow: ~1.07:1 as accent text/links on white — below the 3:1 UI bar.
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#fde047")
        }
    }

    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }

    @Test("validateAccentFamily returns failures naming token + mode")
    func validationNamesFailures() {
        let fails = Color.validateAccentFamily(lightAccentHex: "#fde047",
                                               darkAccentHex: Color.darkAccent(from: "#fde047"))
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("as text") })
        #expect(fails.allSatisfy { !$0.token.isEmpty && $0.ratio < $0.target })
    }

    @Test("includeNeutrals: false is byte-for-byte the accent-only output (no neutral tokens)")
    func accentOnlyUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", includeNeutrals: false)
        #expect(a == b)
        #expect(!a.contains("--sw-surface"))
        #expect(!a.contains("@media"))
    }

    @Test("includeNeutrals: true emits the neutral ramp and a prefers-contrast block")
    func fullPaletteEmitted() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("--sw-text: light-dark(#"))
        #expect(css.contains("--sw-border: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("--neutrals"))   // header mentions the flag
    }

    @Test("Status seeds emit raw --sw-danger/--sw-success lines, no neutral tokens, no @media")
    func statusSeedsEmit() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", successHex: "#059669")
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(css.contains("--sw-success: light-dark(#059669, #"))
        #expect(!css.contains("--sw-surface"))   // no neutrals
        #expect(!css.contains("@media"))          // status colors need no media block
        // ordering: accent, then danger, then success
        let iAccent = css.range(of: "--sw-accent:")!.lowerBound
        let iDanger = css.range(of: "--sw-danger:")!.lowerBound
        let iSuccess = css.range(of: "--sw-success:")!.lowerBound
        #expect(iAccent < iDanger && iDanger < iSuccess)
    }

    @Test("Only the supplied status flag is emitted")
    func oneStatusSeedOnly() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48")
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(!css.contains("--sw-success"))
    }

    @Test("No status seeds is byte-for-byte the accent-only output")
    func noStatusSeedsUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: nil, successHex: nil)
        #expect(a == b)
        #expect(!a.contains("--sw-danger"))
    }

    @Test("No status seeds is byte-for-byte the accent+neutrals output")
    func noStatusSeedsUnchangedWithNeutrals() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)
        let b = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                         dangerHex: nil, successHex: nil, includeNeutrals: true)
        #expect(a == b)
    }

    @Test("Status seeds compose with --neutrals (status lines + neutral ramp + media block)")
    func statusComposesWithNeutrals() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", includeNeutrals: true)
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        // danger appears before the neutral ramp
        #expect(css.range(of: "--sw-danger:")!.lowerBound < css.range(of: "--sw-surface:")!.lowerBound)
    }

    @Test("A contrast-failing status seed throws PaletteError")
    func badStatusSeedThrows() {
        #expect(throws: Color.PaletteError.self) {
            // pale pink danger: raw < 4.5 on white
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#f5a3a3")
        }
    }

    @Test("An invalid status hex throws invalidHex")
    func invalidStatusHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", successHex: "nope")
        }
    }

    @Test("Shipped warning default passes the status validator (raw 3:1 + strong 4.5/7)") func shippedWarningAccessible() {
        // The base-sheet default is hand-authored light-dark(#b45309, #fbbf24) — guard it stays accessible.
        #expect(Color.validateStatusFamily(name: "--sw-warning",
                                           lightHex: "#b45309", darkHex: "#fbbf24",
                                           rawBar: 3.0).isEmpty)
    }

    @Test("warning/info seeds emit raw lines in order accent→danger→success→warning→info") func warningInfoEmit() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", successHex: "#059669",
                                           warningHex: "#d97706", infoHex: "#0284c7")
        for t in ["--sw-danger:", "--sw-success:", "--sw-warning:", "--sw-info:"] {
            #expect(css.contains(t))
        }
        let i = { (s: String) in css.range(of: s)!.lowerBound }
        #expect(i("--sw-accent:") < i("--sw-danger:"))
        #expect(i("--sw-danger:") < i("--sw-success:"))
        #expect(i("--sw-success:") < i("--sw-warning:"))
        #expect(i("--sw-warning:") < i("--sw-info:"))
    }

    @Test("No warning/info seeds is byte-for-byte the prior output") func noWarningInfoUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48",
                                         warningHex: nil, infoHex: nil)
        #expect(a == b)
        #expect(!a.contains("--sw-warning"))
        #expect(!a.contains("--sw-info"))
    }

    @Test("A washed warning seed throws") func badWarningThrows() {
        #expect(throws: Color.PaletteError.self) {
            // amber-500 #f59e0b is 2.15:1 on white — below the 3:1 border bar.
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", warningHex: "#f59e0b")
        }
    }
}
