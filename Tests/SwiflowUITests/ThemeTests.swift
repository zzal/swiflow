// Tests/SwiflowUITests/ThemeTests.swift
import Testing
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
        #expect(css.contains("color-scheme: light dark"))   // enables light-dark() responsiveness
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
            "--sw-danger", "--sw-success", "--sw-transition", "--sw-anim-duration",
            "--sw-overlay-bg", "--sw-backdrop-blur",
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
    }

    @Test("Reduced-motion layer collapses the motion tokens") func reducedMotionRepoints() {
        let css = sheet
        #expect(css.contains("--sw-transition: none"))
        #expect(css.contains("--sw-anim-duration: 0s"))
    }

    @Test("Contrast layer thickens the border and color-gamut upgrades to display-p3") func contrastAndGamutRepoints() {
        let css = sheet
        #expect(css.contains("--sw-border-width: 2px"))   // prefers-contrast: more
        #expect(css.contains("color(display-p3"))         // color-gamut: p3
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
}
