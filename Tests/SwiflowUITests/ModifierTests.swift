// Tests/SwiflowUITests/ModifierTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Modifiers")
@MainActor
struct ModifierTests {
    @Test(".padding adds the token var without disturbing existing styles") func paddingAppendsTokenVar() {
        let s = styleOf(VStack { text("x") }.padding(.lg))
        #expect(s["padding"] == "var(--sw-space-lg)")
        #expect(s["display"] == "flex")   // doesn't disturb existing styles
    }

    @Test(".gap overrides the spacing set in the stack constructor") func gapModifierOverridesConstructorGap() {
        let s = styleOf(VStack(spacing: .md) { text("x") }.gap(.sm))
        #expect(s["gap"] == "var(--sw-space-sm)")
    }

    @Test(".custom spacing passes its raw CSS value through") func customSpacingPassesThrough() {
        #expect(styleOf(HStack { text("x") }.padding(.custom("3px")))["padding"] == "3px")
    }
}
