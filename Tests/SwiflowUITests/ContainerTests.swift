// Tests/SwiflowUITests/ContainerTests.swift
// Container is the simplest layout primitive: a stateless centered max-width
// <div> over the --sw-container-{sm,md,lg,xl} tokens (Badge's shape — variant enum
// with a modifierClass → sw-container--<variant>, caller attrs/.class merge).
// Default size is .lg.
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@Suite("Container")
@MainActor
struct ContainerTests {
    @Test("renders a div with the default lg variant class") func renders() {
        let c = el(Container { text("x") })!
        #expect(c.tag == "div")
        #expect(c.attributes["class"] == "sw-container sw-container--lg")
    }

    @Test("sm/md/xl variants map to the modifier class") func variants() {
        #expect(el(Container(size: .sm) { text("x") })!.attributes["class"] == "sw-container sw-container--sm")
        #expect(el(Container(size: .md) { text("x") })!.attributes["class"] == "sw-container sw-container--md")
        #expect(el(Container(size: .xl) { text("x") })!.attributes["class"] == "sw-container sw-container--xl")
    }

    @Test("children render in order") func childrenOrder() {
        let c = el(Container { text("a"); text("b"); text("c") })!
        #expect(c.children.count == 3)
        #expect(c.children == [.text("a"), .text("b"), .text("c")])
    }

    @Test("caller attributes and class merge onto the container") func callerMerge() {
        let c = el(Container(.class("hero"), .attr("id", "page-shell")) { text("x") })!
        #expect(c.attributes["class"] == "sw-container sw-container--lg hero")
        #expect(c.attributes["id"] == "page-shell")
    }
}
