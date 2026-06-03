// Tests/SwiflowUITests/ThemeTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@Suite("Theme", .serialized)
@MainActor
struct ThemeTests {
    @Test func baseSheetContainsRootTokens() {
        let css = SwiflowUI.baseStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(":root"))
        #expect(css.contains("--sw-space-md"))
        #expect(css.contains("--sw-accent"))
        // :root must NOT be scoped (CSSSheet leaves it alone).
        #expect(!css.contains(".swiflow"))
    }

    @Test func installBaseStylesEmitsOnce() {
        StyleInjectionRegistry.reset()
        var ids: [String] = []
        StyleInjectionRegistry.emit = { id, _ in ids.append(id) }
        defer { StyleInjectionRegistry.emit = nil; StyleInjectionRegistry.reset() }

        SwiflowUI.installBaseStyles()
        SwiflowUI.installBaseStyles()
        #expect(ids == ["swiflow-ui-base"])
    }
}
