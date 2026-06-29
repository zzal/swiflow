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
    @Test(".padding(.all) emits the four atomic logical longhands, no shorthand") func paddingAllEdges() {
        let s = styleOf(VStack { text("x") }.padding(.lg))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-end"] == "var(--sw-space-lg)")
        #expect(s["padding"] == nil)        // no shorthand emitted
        #expect(s["display"] == "flex")     // doesn't disturb existing styles
    }

    @Test(".gap overrides the spacing set in the stack constructor") func gapModifierOverridesConstructorGap() {
        let s = styleOf(VStack(spacing: .md) { text("x") }.gap(.sm))
        #expect(s["gap"] == "var(--sw-space-sm)")
    }

    @Test(".custom spacing passes its raw CSS value through to every edge") func customSpacingPassesThrough() {
        let s = styleOf(HStack { text("x") }.padding(.custom("3px")))
        #expect(s["padding-block-start"] == "3px")
        #expect(s["padding-inline-end"] == "3px")
    }

    @Test(".horizontal pads only the inline edges") func paddingHorizontal() {
        let s = styleOf(VStack { text("x") }.padding(.lg, .horizontal))
        #expect(s["padding-inline-start"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-end"] == "var(--sw-space-lg)")
        #expect(s["padding-block-start"] == nil)
        #expect(s["padding-block-end"] == nil)
    }

    @Test(".vertical pads only the block edges") func paddingVertical() {
        let s = styleOf(VStack { text("x") }.padding(.lg, .vertical))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("an explicit edge subset pads exactly those edges") func paddingSubset() {
        let s = styleOf(VStack { text("x") }.padding(.sm, [.top, .leading]))
        #expect(s["padding-block-start"] == "var(--sw-space-sm)")    // top
        #expect(s["padding-inline-start"] == "var(--sw-space-sm)")   // leading
        #expect(s["padding-block-end"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("a single edge with a custom length") func paddingSingleEdgeCustom() {
        let s = styleOf(VStack { text("x") }.padding(.custom("3px"), .bottom))
        #expect(s["padding-block-end"] == "3px")
        #expect(s["padding-block-start"] == nil)
        #expect(s["padding-inline-start"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("chained directional calls compose deterministically (later overrides its edges only)") func paddingComposition() {
        let s = styleOf(VStack { text("x") }.padding(.lg).padding(.md, .horizontal))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")    // unchanged by the 2nd call
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == "var(--sw-space-md)")   // overridden
        #expect(s["padding-inline-end"] == "var(--sw-space-md)")
    }
}
