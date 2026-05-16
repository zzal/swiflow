// Tests/SwiflowTests/DiffTests/FirstMountTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — first mount")
struct FirstMountTests {
    @Test("First mount of a text node emits createText only")
    func textFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .text("hello"),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createText(handle: 0, text: "hello")])
        #expect(result.newMountTree.handle == 0)
        #expect(result.newMountTree.vnode == .text("hello"))
        #expect(result.newMountTree.children.isEmpty)
    }

    @Test("First mount of a rawHTML node emits createRawHTML only")
    func rawHTMLFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .rawHTML("<b>x</b>"),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createRawHTML(handle: 0, html: "<b>x</b>")])
    }

    @Test("First mount of an empty div emits createElement only")
    func emptyDivFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div")),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createElement(handle: 0, tag: "div")])
    }

    @Test("First mount of a div with attributes emits set patches in order")
    func divWithAttributesFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "div",
                attributes: ["class": "row", "id": "main"]
            )),
            handles: handles,
            handlers: handlers
        )
        // First patch must be createElement; attribute order is non-deterministic
        // across dictionary iteration, so verify by membership.
        #expect(result.patches.first == .createElement(handle: 0, tag: "div"))
        #expect(result.patches.contains(.setAttribute(handle: 0, name: "class", value: "row")))
        #expect(result.patches.contains(.setAttribute(handle: 0, name: "id", value: "main")))
        #expect(result.patches.count == 3)
    }

    @Test("First mount of a parent with two children wires appendChild")
    func parentWithTwoChildrenFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "ul",
                children: [.text("a"), .text("b")]
            )),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [
            .createElement(handle: 0, tag: "ul"),
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
        #expect(result.newMountTree.children.count == 2)
        #expect(result.newMountTree.children[0].handle == 1)
        #expect(result.newMountTree.children[1].handle == 2)
    }

    @Test("First mount of an element with a handler registers and emits addHandler")
    func elementWithHandlerFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let handler = handlers.register { _ in }
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "button",
                handlers: ["click": handler]
            )),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [
            .createElement(handle: 0, tag: "button"),
            .addHandler(handle: 0, event: "click", handlerId: handler.id),
        ])
        #expect(result.newMountTree.handlerIds["click"] == handler.id)
    }
}
