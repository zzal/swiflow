// Tests/SwiflowTests/DSLTests.swift
import Testing
@testable import Swiflow

@Suite("DSL — ChildrenBuilder")
struct ChildrenBuilderTests {

    @ChildrenBuilder
    private func empty() -> [VNode] {}

    @ChildrenBuilder
    private func singleText() -> [VNode] {
        VNode.text("hi")
    }

    @ChildrenBuilder
    private func multiple() -> [VNode] {
        VNode.text("a")
        VNode.text("b")
        VNode.text("c")
    }

    @ChildrenBuilder
    private func conditional(_ flag: Bool) -> [VNode] {
        VNode.text("always")
        if flag {
            VNode.text("conditionally")
        }
    }

    @ChildrenBuilder
    private func eitherOr(_ flag: Bool) -> [VNode] {
        if flag {
            VNode.text("yes")
        } else {
            VNode.text("no")
        }
    }

    @ChildrenBuilder
    private func arrayLiteral() -> [VNode] {
        for s in ["x", "y", "z"] {
            VNode.text(s)
        }
    }

    @Test("Empty block produces no children")
    func emptyProducesNone() {
        #expect(empty().isEmpty)
    }

    @Test("Single expression produces one child")
    func singleProducesOne() {
        #expect(singleText() == [.text("hi")])
    }

    @Test("Multiple expressions produce ordered children")
    func multipleProducesAll() {
        #expect(multiple() == [.text("a"), .text("b"), .text("c")])
    }

    @Test("Optional branch is included or skipped based on condition")
    func optionalIncludesWhenTrue() {
        #expect(conditional(true) == [.text("always"), .text("conditionally")])
        #expect(conditional(false) == [.text("always")])
    }

    @Test("Either branch picks one side")
    func eitherPicksBranch() {
        #expect(eitherOr(true) == [.text("yes")])
        #expect(eitherOr(false) == [.text("no")])
    }

    @Test("For-loop produces all iterations")
    func forLoopProducesAll() {
        #expect(arrayLiteral() == [.text("x"), .text("y"), .text("z")])
    }
}
