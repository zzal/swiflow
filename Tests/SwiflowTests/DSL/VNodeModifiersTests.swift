// Tests/SwiflowTests/DSL/VNodeModifiersTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("VNode postfix modifiers")
struct VNodeModifiersTests {
    @Test(".class appends to the attributes bag")
    func classOnElement() {
        let v = div { }.class("row")
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["class"] == "row")
    }

    @Test(
        ".class on a non-element triggers a diagnostic crash in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func classOnText() async {
        await #expect(processExitsWith: .failure) {
            let text: VNode = .text("hi")
            _ = text.class("row")
        }
    }

    @Test(".id, .style, .attr, .data compose")
    func compose() {
        let v = div { }
            .id("hero")
            .class("container")
            .style("padding", "1rem")
            .attr("role", "main")
            .data("user-id", "42")
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["id"] == "hero")
        #expect(data.attributes["class"] == "container")
        #expect(data.style["padding"] == "1rem")
        #expect(data.attributes["role"] == "main")
        #expect(data.attributes["data-user-id"] == "42")
    }

    @Test(".attr typed overloads work in postfix position")
    func typedAttrPostfix() {
        let v = input().attr("rows", 5).attr("step", 0.5)
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["rows"] == "5")
        #expect(data.attributes["step"] == "0.5")
    }
}

/// Helper for `.disabled(if:)` on the exit-test crash cases.
private var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
