// Tests/SwiflowUITests/TokensTests.swift
import Testing
@testable import SwiflowUI

@Suite("Tokens")
struct TokensTests {
    @Test func spacingMapsToVars() {
        #expect(Spacing.none.css == "0")
        #expect(Spacing.xs.css == "var(--sw-space-xs)")
        #expect(Spacing.md.css == "var(--sw-space-md)")
        #expect(Spacing.xl.css == "var(--sw-space-xl)")
        #expect(Spacing.custom("13px").css == "13px")
    }
    @Test func spacingIsEquatable() {
        #expect(Spacing.md == Spacing.md)
        #expect(Spacing.md != Spacing.none)
    }
    @Test func crossAlignMapsToAlignItems() {
        #expect(CrossAlign.start.css == "flex-start")
        #expect(CrossAlign.center.css == "center")
        #expect(CrossAlign.end.css == "flex-end")
        #expect(CrossAlign.stretch.css == "stretch")
        #expect(CrossAlign.baseline.css == "baseline")
    }
    @Test func mainAlignMapsToJustifyContent() {
        #expect(MainAlign.start.css == "flex-start")
        #expect(MainAlign.center.css == "center")
        #expect(MainAlign.end.css == "flex-end")
        #expect(MainAlign.between.css == "space-between")
        #expect(MainAlign.around.css == "space-around")
        #expect(MainAlign.evenly.css == "space-evenly")
    }
}
