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

    @Test(".handler produces a handler entry that dispatches the registered closure")
    func onModifier() {
        var fired = false
        let registry = HandlerRegistry()
        let h = registry.register { _ in fired = true }
        let attr = Attribute.handler(event: "click", value: h)
        let data = applyAttributes(tag: "button", [attr])
        #expect(data.handlers["click"] != nil)
        // Dispatch directly to assert wiring.
        data.handlers["click"]?.invoke(EventInfo(type: "click"))
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

@Suite("DSL — element factories")
struct ElementFactoryTests {

    @Test("div with no attrs and no children")
    func bareDiv() {
        let node = div()
        #expect(node == .element(ElementData(tag: "div")))
    }

    @Test("div with class and child text")
    func divWithClassAndChild() {
        let node = div(.class("row")) {
            VNode.text("hi")
        }
        let expected = VNode.element(ElementData(
            tag: "div",
            attributes: ["class": "row"],
            children: [.text("hi")]
        ))
        #expect(node == expected)
    }

    @Test("h1 with text-only convenience overload")
    func h1Text() {
        let node = h1("Hello")
        let expected = VNode.element(ElementData(
            tag: "h1",
            children: [.text("Hello")]
        ))
        #expect(node == expected)
    }

    @Test("button with handler and text body")
    func buttonWithHandler() {
        let registry = HandlerRegistry()
        let h = registry.register { _ in }
        let node = button("Click", .handler(event: "click", value: h))
        let expected = VNode.element(ElementData(
            tag: "button",
            handlers: ["click": h],
            children: [.text("Click")]
        ))
        #expect(node == expected)
    }

    @Test("ul with mapped children")
    func ulMappedChildren() {
        let items = ["a", "b", "c"]
        let node = ul {
            for item in items {
                li { VNode.text(item) }
            }
        }
        let expected = VNode.element(ElementData(
            tag: "ul",
            children: items.map { i in
                .element(ElementData(tag: "li", children: [.text(i)]))
            }
        ))
        #expect(node == expected)
    }

    @Test("input self-closing with property")
    func inputWithProperty() {
        let node = input(.prop("value", .string("x")), .attr("type", "text"))
        let expected = VNode.element(ElementData(
            tag: "input",
            attributes: ["type": "text"],
            properties: ["value": .string("x")]
        ))
        #expect(node == expected)
    }
}

@Suite("DSL — rawHTML escape hatch")
struct RawHTMLDSLTests {
    @Test("rawHTML produces a VNode.rawHTML case")
    func producesRawHTMLCase() {
        let node = rawHTML("<svg/>")
        #expect(node == .rawHTML("<svg/>"))
    }

    @Test("rawHTML can be embedded as a child")
    func embedAsChild() {
        let node = div { rawHTML("<b>x</b>") }
        let expected = VNode.element(ElementData(
            tag: "div",
            children: [.rawHTML("<b>x</b>")]
        ))
        #expect(node == expected)
    }
}
