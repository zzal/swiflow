// Tests/SwiflowUITests/ThemeTests.swift
import Testing
import Foundation
import Swiflow
@testable import SwiflowUI

// installBaseStylesEmitsOnce mutates the @MainActor StyleInjectionRegistry
// global, but both test bodies are synchronous @MainActor — they run
// atomically with no suspension points, so no .serialized is needed.
@Suite("Theme")
@MainActor
struct ThemeTests {
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    @Test("Base stylesheet defines :root tokens and leaves :root unscoped") func baseSheetContainsRootTokens() {
        let css = sheet
        #expect(css.contains(":root"))
        // Load-bearing for both light-dark() AND native form-control dark rendering (M4).
        #expect(css.contains("color-scheme: light dark"))
        #expect(css.contains("--sw-space-md"))
        #expect(css.contains("--sw-accent"))
        #expect(css.contains("--sw-border"))
        // :root must NOT be scoped (CSSSheet leaves it alone).
        #expect(!css.contains(".swiflow"))
    }

    @Test("Forward-contract tokens are all present in the base layer") func forwardContractTokens() {
        let css = sheet
        for token in [
            "--sw-radius-sm", "--sw-surface-2", "--sw-text-muted", "--sw-accent-text",
            "--sw-danger", "--sw-success", "--sw-duration", "--sw-ease", "--sw-anim-play",
            "--sw-focus-ring", "--sw-focus-ring-width", "--sw-disabled-opacity",
            "--sw-overlay-bg", "--sw-backdrop", "--sw-accent-hover", "--sw-accent-active", "--sw-shadow",
            "--sw-accent-strong", "--sw-danger-strong", "--sw-success-strong", "--sw-bg",
            "--sw-warning", "--sw-info", "--sw-warning-strong", "--sw-info-strong",
        ] {
            #expect(css.contains(token), "missing token \(token)")
        }
    }

    @Test("All four media-feature override layers are emitted") func mediaLayersEmitted() {
        let css = sheet
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("@media (prefers-reduced-motion: reduce)"))
        #expect(css.contains("@media (prefers-reduced-transparency: reduce)"))
        #expect(css.contains("@media (color-gamut: p3)"))
        #expect(css.contains("@supports (color: color(display-p3 0 0 0))"))  // p3 syntax gate
    }

    @Test("Reduced-motion layer collapses duration and pauses animation") func reducedMotionRepoints() {
        let css = sheet
        #expect(css.contains("--sw-duration: 0s"))
        #expect(css.contains("--sw-anim-play: paused"))
    }

    @Test("Contrast layer thickens the border and color-gamut upgrades to display-p3") func contrastAndGamutRepoints() {
        let css = sheet
        #expect(css.contains("--sw-border-width: 2px"))   // prefers-contrast: more
        #expect(css.contains("color(display-p3"))         // color-gamut: p3
    }

    @Test("Override layers are emitted after the base :root so they win the cascade") func overridesComeAfterBase() {
        let css = sheet
        let base = css.range(of: "--sw-border-width: 1px")
        let override = css.range(of: "@media (prefers-contrast: more)")
        #expect(base != nil && override != nil)
        if let base, let override { #expect(base.lowerBound < override.lowerBound) }
    }

    @Test("The reduced-motion layer re-points only motion tokens (no cross-clobber)") func reducedMotionLayerIsolated() {
        // Each chunk after splitting on the at-rule keyword is one block's body.
        let block = sheet.components(separatedBy: "@media").first { $0.contains("prefers-reduced-motion") }
        #expect(block != nil)
        if let block {
            #expect(block.contains("--sw-duration: 0s"))
            #expect(block.contains("--sw-anim-play: paused"))
            // Non-motion tokens must not appear in this layer.
            #expect(!block.contains("--sw-accent"))
            #expect(!block.contains("--sw-border-width"))
            #expect(!block.contains("--sw-overlay-bg"))
        }
    }

    @Test("The raw sheet has balanced braces (guards against truncation/merge)") func bracesBalanced() {
        let css = sheet
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }

    @Test("installBaseStyles emits the base sheet once even when called twice") func installBaseStylesEmitsOnce() {
        StyleInjectionRegistry.reset()
        var ids: [String] = []
        StyleInjectionRegistry.emit = { id, _ in ids.append(id) }
        defer { StyleInjectionRegistry.emit = nil; StyleInjectionRegistry.reset() }

        SwiflowUI.installBaseStyles()
        SwiflowUI.installBaseStyles()
        #expect(ids == ["swiflow-ui-base"])
    }

    @Test("Accent hover/active derive from --sw-accent with a calc lightness step")
    func accentRampDerivesFromAccent() {
        let css = sheet
        for token in ["--sw-accent-hover", "--sw-accent-active"] {
            #expect(css.contains("\(token): light-dark(#"), "\(token) missing literal fallback")
        }
        #expect(css.contains("--sw-accent-hover: light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h)"),
                "hover missing derived layer")
        #expect(css.contains("--sw-accent-active: light-dark(oklch(from var(--sw-accent) calc(l - 0.16) c h)"),
                "active missing derived layer")
    }

    @Test("Each derived text token ships a static fallback AND a dynamic layer")
    func progressiveEnhancementPairsEmitted() {
        let css = sheet
        // -strong: a light-dark hex fallback and an oklch(from …) dynamic layer.
        for token in ["--sw-accent-strong", "--sw-danger-strong", "--sw-success-strong"] {
            let hue = token.replacingOccurrences(of: "-strong", with: "")  // e.g. --sw-accent
            #expect(css.contains("\(token): light-dark(#"), "\(token) missing static fallback")
            #expect(css.contains("oklch(from var(\(hue))"), "\(token) missing oklch(from …) dynamic layer")
        }
        // -text: dark fallback + contrast-color dynamic layer.
        #expect(css.contains("--sw-accent-text: light-dark(#0b1220, #0b1220)"))
        #expect(css.contains("--sw-accent-text: contrast-color(var(--sw-accent))"))
    }

    @Test("Base tokens live in @layer swiflow.base so unlayered app overrides win")
    func baseTokensAreLayered() {
        let css = sheet
        #expect(css.contains("@layer swiflow.base"))
        #expect(css.contains("--sw-accent"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)   // braces balanced
    }

    @Test("Scalar tokens are registered with @property (typed + animatable)") func scalarPropertyRegistration() {
        let css = sheet
        // The @property block must be emitted OUTSIDE @layer swiflow.base (layer-agnostic at-rule).
        #expect(css.contains("@property --sw-border-width"))
        #expect(css.contains("@property --sw-duration"))
        #expect(css.contains("@property --sw-radius"))
        #expect(css.contains("@property --sw-disabled-opacity"))
        // Each registration carries syntax + inherits + initial-value.
        #expect(css.contains(#"@property --sw-border-width { syntax: "<length>"; inherits: true; initial-value: 1px; }"#))
        #expect(css.contains(#"@property --sw-duration { syntax: "<time>"; inherits: true; initial-value: 150ms; }"#))
        #expect(css.contains(#"@property --sw-disabled-opacity { syntax: "<number>"; inherits: true; initial-value: 0.5; }"#))
        // The block precedes the cascade layer in source order.
        let propIdx = css.range(of: "@property --sw-space-xs")!.lowerBound
        let layerIdx = css.range(of: "@layer swiflow.base")!.lowerBound
        #expect(propIdx < layerIdx)
    }

    @Test("Color tokens are registered AND keep their literal→oklch double-declaration") func colorPropertyRegistration() {
        let css = sheet
        #expect(css.contains(#"@property --sw-accent { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }"#))
        #expect(css.contains(#"@property --sw-bg { syntax: "<color>"; inherits: true; initial-value: #f6f7f9; }"#))
        // The progressive fallback MUST stay physically present: literal line first,
        // oklch(from …) line second. Registration must not collapse it.
        #expect(css.contains("--sw-accent-hover: light-dark(#"))
        #expect(css.contains("--sw-accent-hover: light-dark(oklch(from var(--sw-accent)"))
    }

    @Test("warning/info status tokens are present across the right layers") func warningInfoTokens() {
        let css = sheet
        // :root defaults — warning is a literal amber; info aliases the accent.
        #expect(css.contains("--sw-warning: light-dark(#b45309, #fbbf24)"))
        #expect(css.contains("--sw-info: var(--sw-accent)"))
        // -strong derivations exist for both.
        #expect(css.contains("--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.40 c h)"))
        #expect(css.contains("--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.40 c h)"))
        // more-contrast pushes both strong tokens to the 0.30/0.88 band.
        #expect(css.contains("--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.30 c h)"))
        #expect(css.contains("--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.30 c h)"))
        // warning has its own P3 raw line; info does NOT (it inherits the accent's via var()).
        #expect(css.contains("--sw-warning: light-dark(color(display-p3"))
        #expect(!css.contains("--sw-info: light-dark(color(display-p3"))
        // wrapping kept braces balanced.
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
