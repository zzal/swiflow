// Tests/SwiflowUITests/StackTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Stack")
@MainActor
struct StackTests {
    @Test("VStack lowers to flex column with gap/align/justify mapped to CSS") func vstackLowersToFlexColumn() {
        let s = styleOf(VStack(spacing: .md, align: .center, justify: .between) { text("x") })
        #expect(s["display"] == "flex")
        #expect(s["flex-direction"] == "column")
        #expect(s["gap"] == "var(--sw-space-md)")
        #expect(s["align-items"] == "center")
        #expect(s["justify-content"] == "space-between")
    }

    @Test("HStack lowers to flex row with stretch/flex-start defaults") func hstackLowersToFlexRow() {
        let s = styleOf(HStack { text("x") })
        #expect(s["display"] == "flex")
        #expect(s["flex-direction"] == "row")
        #expect(s["align-items"] == "stretch")        // default
        #expect(s["justify-content"] == "flex-start") // default
    }

    @Test("Default .none spacing emits no gap property") func gapOmittedWhenNone() {
        let s = styleOf(VStack { text("x") })   // spacing default .none
        #expect(s["gap"] == nil)
    }

    @Test("Stack renders as a div keeping its children intact") func preservesChildren() {
        let node = VStack { text("a"); text("b") }
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.children.count == 2)
        #expect(data.tag == "div")
    }

    @Test("Caller-supplied style wins over the stack's flex defaults") func callerAttributesOverrideDefaults() {
        // A caller-supplied style wins (last-write-wins in applyAttributes).
        let node = HStack(.style("display", "grid")) { text("x") }
        #expect(styleOf(node)["display"] == "grid")
    }

    @Test("Caller .class lands on the stack without disturbing its flex styles") func callerClassAddsCleanly() {
        let node = VStack(.class("hero")) { text("x") }
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.attributes["class"] == "hero")   // nothing to clobber — stacks carry no class
        #expect(data.style["display"] == "flex")
    }
}
