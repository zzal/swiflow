// Tests/SwiflowUITests/SpacerTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Spacer")
@MainActor
struct SpacerTests {
    @Test("Spacer grows to fill free space via flex-grow:1") func spacerGrows() {
        #expect(styleOf(Spacer())["flex-grow"] == "1")
    }

    @Test("Default minLength emits no flex-basis") func basisOmittedWhenNone() {
        #expect(styleOf(Spacer())["flex-basis"] == nil)
    }

    @Test("minLength sets flex-basis from the token scale") func minLengthSetsBasis() {
        #expect(styleOf(Spacer(minLength: .lg))["flex-basis"] == "var(--sw-space-lg)")
    }

    @Test("custom minLength passes its raw length through") func customMinLengthPassesThrough() {
        #expect(styleOf(Spacer(minLength: .custom("40px")))["flex-basis"] == "40px")
    }

    @Test("Spacer renders as an empty div with no children") func rendersEmptyDiv() {
        guard case .element(let data) = Spacer() else { Issue.record("not element"); return }
        #expect(data.tag == "div")
        #expect(data.children.isEmpty)
    }

    @Test("Caller attributes land on the spacer") func callerAttributesLand() {
        guard case .element(let data) = Spacer(.class("push")) else { Issue.record("not element"); return }
        #expect(data.attributes["class"] == "push")
        #expect(data.style["flex-grow"] == "1")
    }

    @Test("Caller style wins over the spacer's flex-grow (last-write-wins)") func callerStyleDefeatsGrow() {
        #expect(styleOf(Spacer(.style("flex-grow", "0")))["flex-grow"] == "0")
    }
}
