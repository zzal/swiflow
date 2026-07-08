// Tests/SwiflowUITests/PopoverTransitionTests.swift
//
// Audit V Wave-2 #3: the shared entry/exit quartet. The contract every
// overlay relies on: closed state carries opacity/transform + the 4-part
// transition (overlay+display with allow-discrete so the exit ANIMATES
// before the top-layer teardown); `display` appears ONLY in the open state
// (an author display in the base rule would beat the UA's closed
// display:none); @starting-style re-states the closed values so the ENTRY
// animates from them.
import Testing
@testable import SwiflowUI

@Suite("popoverTransitionCSS")
struct PopoverTransitionTests {

    private let block = popoverTransitionCSS(
        base: ".sw-x__panel", open: ".sw-x__panel:popover-open",
        closedTransform: "translateY(-4px)", openTransform: "translateY(0)",
        openExtras: "\n      display: block;")

    @Test("the quartet is complete: 4-part transition, open state, @starting-style")
    func quartetComplete() {
        #expect(block.contains("overlay var(--sw-duration) var(--sw-ease) allow-discrete"))
        #expect(block.contains("display var(--sw-duration) var(--sw-ease) allow-discrete"))
        #expect(block.contains(".sw-x__panel:popover-open"))
        #expect(block.contains("@starting-style"))
    }

    @Test("display: appears in the OPEN state only — never the base rule")
    func displayOnOpenOnly() {
        // The base rule is everything before the open selector's first use.
        let baseRule = String(block.split(separator: "}").first ?? "")
        #expect(!baseRule.contains("display: "),
                "an author display in the base rule beats the UA's closed display:none")
        #expect(block.contains("display: block;"))
    }

    @Test("@starting-style re-states the CLOSED transform so entry animates from it")
    func startingStyleMatchesClosed() {
        let starting = block.range(of: "@starting-style").map { String(block[$0.lowerBound...]) } ?? ""
        #expect(starting.contains("translateY(-4px)"))
        #expect(starting.contains("opacity: 0"))
    }
}
