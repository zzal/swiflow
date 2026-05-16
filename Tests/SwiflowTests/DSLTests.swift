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

@Suite("DSL — Attribute modifiers")
struct AttributeModifierTests {

    @Test(".class produces an attribute named 'class'")
    func classModifier() {
        let attr = Attribute.class("row")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["class": "row"])
    }

    @Test(".id produces an attribute named 'id'")
    func idModifier() {
        let attr = Attribute.id("main")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["id": "main"])
    }

    @Test(".attr produces an arbitrary attribute")
    func attrModifier() {
        let attr = Attribute.attr("data-foo", "bar")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["data-foo": "bar"])
    }

    @Test(".prop produces a property")
    func propModifier() {
        let attr = Attribute.prop("value", .string("x"))
        let data = applyAttributes(tag: "input", [attr])
        #expect(data.properties == ["value": .string("x")])
    }

    @Test(".style produces an inline style declaration")
    func styleModifier() {
        let attr = Attribute.style("color", "red")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.style == ["color": "red"])
    }

    @Test(".key sets the element key")
    func keyModifier() {
        let attr = Attribute.key("k1")
        let data = applyAttributes(tag: "li", [attr])
        #expect(data.key == "k1")
    }

    @Test(".on produces a handler entry (uses ambient registry)")
    func onModifier() {
        var fired = false
        let attr = Attribute.on("click", HandlerRegistry.testInstance.register { _ in fired = true })
        let data = applyAttributes(tag: "button", [attr])
        #expect(data.handlers["click"] != nil)
        // Dispatch directly to assert wiring.
        data.handlers["click"]?.invoke(Event(type: "click"))
        #expect(fired)
    }

    @Test("Multiple modifiers of the same category merge in declaration order")
    func multipleMergeInOrder() {
        let data = applyAttributes(tag: "div", [
            .class("a"),
            .style("color", "red"),
            .style("font-size", "12px"),
        ])
        #expect(data.attributes == ["class": "a"])
        #expect(data.style == ["color": "red", "font-size": "12px"])
    }

    @Test("Later modifier of same key overrides earlier")
    func laterOverrides() {
        let data = applyAttributes(tag: "div", [
            .class("a"),
            .class("b"),
        ])
        #expect(data.attributes == ["class": "b"])
    }
}

// HandlerRegistry.testInstance — a process-wide convenience for tests.
// Production code uses an injected registry; this just keeps the DSL tests
// readable. `nonisolated(unsafe)` is fine here: registry is non-Sendable in
// Phase 1 (deferred to Phase 3) and the test suite is single-threaded.
extension HandlerRegistry {
    nonisolated(unsafe) static let testInstance = HandlerRegistry()
}
