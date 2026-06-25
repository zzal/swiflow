import Testing
import Swiflow
@testable import SwiflowUI

@Suite("ThemeToken")
struct ThemeTokenTests {
    @Test("Typed statics map to the right --sw-* names")
    func typedStatics() {
        #expect(ThemeToken.accent("#7c3aed") == ThemeToken(name: "--sw-accent", value: "#7c3aed"))
        #expect(ThemeToken.radius("12px").name  == "--sw-radius")
        #expect(ThemeToken.surface("#fff").name == "--sw-surface")
        #expect(ThemeToken.text("#111").name    == "--sw-text")
        #expect(ThemeToken.border("#ccc").name  == "--sw-border")
        #expect(ThemeToken.danger("#dc2626").name  == "--sw-danger")
        #expect(ThemeToken.success("#16a34a").name == "--sw-success")
    }

    @Test(".token is a passthrough escape hatch")
    func tokenEscapeHatch() {
        let t = ThemeToken.token("--sw-space-md", "1rem")
        #expect(t.name == "--sw-space-md")
        #expect(t.value == "1rem")
    }
}

// Mirrors GridTests.swift's helper — pulls the merged inline style dict off a node.
@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Theme")
@MainActor
struct ThemeComponentTests {
    @Test("Theme renders a display:contents div carrying the overrides as custom props")
    func rendersContentsDiv() {
        let node = Theme(.accent("#7c3aed"), .radius("12px")) { text("x") }
        let s = styleOf(node)
        #expect(s["display"] == "contents")
        #expect(s["--sw-accent"] == "#7c3aed")
        #expect(s["--sw-radius"] == "12px")
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.tag == "div")
        #expect(data.children.count == 1)
    }

    @Test(".token override lands as a custom property")
    func tokenOverride() {
        #expect(styleOf(Theme(.token("--sw-space-md", "1rem")) { text("x") })["--sw-space-md"] == "1rem")
    }

    @Test("No tokens still renders a display:contents wrapper")
    func emptyTokens() {
        #expect(styleOf(Theme { text("x") })["display"] == "contents")
    }

    @Test("Nesting renders nested themed divs, each with its own override")
    func nesting() {
        let outer = Theme(.accent("#7c3aed")) { Theme(.radius("4px")) { text("x") } }
        #expect(styleOf(outer)["--sw-accent"] == "#7c3aed")
        guard case .element(let od) = outer, case .element(let inner)? = od.children.first else {
            Issue.record("nesting structure"); return
        }
        #expect(inner.style["--sw-radius"] == "4px")
        #expect(inner.style["display"] == "contents")
    }
}
