// Tests/SwiflowTests/VNodeTests.swift
import Testing
@testable import Swiflow

@Suite("VNode")
struct VNodeTests {
    @Test("Text VNode equality compares string")
    func textEquality() {
        #expect(VNode.text("hi") == VNode.text("hi"))
        #expect(VNode.text("hi") != VNode.text("bye"))
    }

    @Test("RawHTML VNode equality compares string")
    func rawHTMLEquality() {
        #expect(VNode.rawHTML("<b>x</b>") == VNode.rawHTML("<b>x</b>"))
        #expect(VNode.rawHTML("<b>x</b>") != VNode.rawHTML("<i>x</i>"))
        #expect(VNode.text("hi") != VNode.rawHTML("hi"))
    }

    @Test("ElementData equality compares all bags")
    func elementDataEquality() {
        let a = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "x"],
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        let b = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "x"],
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        #expect(a == b)

        let c = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "y"],  // different
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        #expect(a != c)
    }

    @Test("ElementData with same handler IDs is equal even with different closures")
    func handlerEqualityByID() {
        let h1 = EventHandler(id: 7, invoke: { _ in })
        let h2 = EventHandler(id: 7, invoke: { _ in print("different closure") })
        let h3 = EventHandler(id: 8, invoke: { _ in })
        #expect(h1 == h2)
        #expect(h1 != h3)
    }

    @Test("VNode element equality recurses into children")
    func elementRecursesIntoChildren() {
        let leaf: VNode = .text("hello")
        let a = VNode.element(ElementData(
            tag: "div", key: nil, attributes: [:], properties: [:],
            style: [:], handlers: [:], children: [leaf]
        ))
        let b = VNode.element(ElementData(
            tag: "div", key: nil, attributes: [:], properties: [:],
            style: [:], handlers: [:], children: [leaf]
        ))
        #expect(a == b)
    }

    @Test("Event preserves type and optional target value")
    func eventConstruction() {
        let e = EventInfo(type: "input", targetValue: "abc")
        #expect(e.type == "input")
        #expect(e.targetValue == "abc")

        let e2 = EventInfo(type: "click", targetValue: nil)
        #expect(e2.targetValue == nil)
    }

    @Test("environmentOverride VNodes with different env values are not equal")
    func environmentOverrideDifferentValuesAreNotEqual() {
        let a = withEnvironment(\.locale, "fr") { VNode.text("hello") }
        let b = withEnvironment(\.locale, "de") { VNode.text("hello") }
        // Before fix: a == b (wrong — diff skips subtree when locale changes)
        // After fix:  a != b (correct)
        #expect(a != b)
    }

    @Test("environmentOverride VNodes with same env values are equal")
    func environmentOverrideSameValuesAreEqual() {
        let a = withEnvironment(\.locale, "fr") { VNode.text("hello") }
        let b = withEnvironment(\.locale, "fr") { VNode.text("hello") }
        #expect(a == b)
    }
}
