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
    @Test("Base stylesheet defines :root tokens and leaves :root unscoped") func baseSheetContainsRootTokens() {
        let css = SwiflowUI.baseStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(":root"))
        #expect(css.contains("--sw-space-md"))
        #expect(css.contains("--sw-accent"))
        // :root must NOT be scoped (CSSSheet leaves it alone).
        #expect(!css.contains(".swiflow"))
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
