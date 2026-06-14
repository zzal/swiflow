// Tests/SwiflowUITests/DividerTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@Suite("Divider")
@MainActor
struct DividerTests {
    @Test("Divider renders a semantic <hr> using the border tokens") func rendersHrWithTokens() {
        guard let d = elementOf(Divider()) else { Issue.record("not element"); return }
        #expect(d.tag == "hr")
        #expect(d.style["background-color"] == "var(--sw-border)")
        #expect(d.style["border"] == "none")    // the <hr> default rule is reset
        #expect(d.style["margin"] == "0")
        #expect(d.style["align-self"] == "stretch")
    }

    @Test("Horizontal divider sizes its thickness via height, not a border longhand") func horizontalUsesHeight() {
        guard let d = elementOf(Divider(.horizontal)) else { Issue.record("not element"); return }
        #expect(d.style["height"] == "var(--sw-border-width)")
        #expect(d.style["width"] == nil)
        #expect(d.style["min-height"] == nil)              // only the vertical form needs a height floor
        #expect(d.attributes["aria-orientation"] == nil)   // native <hr> default is horizontal
    }

    @Test("Vertical divider sizes via width, floors its height, and declares aria-orientation") func verticalUsesWidthAndAria() {
        guard let d = elementOf(Divider(.vertical)) else { Issue.record("not element"); return }
        #expect(d.style["width"] == "var(--sw-border-width)")
        #expect(d.style["height"] == nil)
        #expect(d.style["min-height"] == "1em")            // stays visible outside a stretch flex row
        #expect(d.attributes["aria-orientation"] == "vertical")
    }

    @Test("Caller attributes win over the divider defaults") func callerAttributesWin() {
        guard let d = elementOf(Divider(.horizontal, .style("background-color", "red"), .class("rule"))) else {
            Issue.record("not element"); return
        }
        #expect(d.style["background-color"] == "red")
        #expect(d.attributes["class"] == "rule")
    }
}
