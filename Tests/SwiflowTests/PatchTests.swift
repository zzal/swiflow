// Tests/SwiflowTests/PatchTests.swift
import Testing
@testable import Swiflow

@Suite("Patch")
struct PatchTests {
    @Test("Lifecycle opcodes equate by handle and payload")
    func lifecycleEquality() {
        #expect(Patch.createElement(handle: 1, tag: "div")
             == Patch.createElement(handle: 1, tag: "div"))
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createElement(handle: 2, tag: "div"))
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createElement(handle: 1, tag: "span"))

        #expect(Patch.createText(handle: 1, text: "x")
             == Patch.createText(handle: 1, text: "x"))
        #expect(Patch.createRawHTML(handle: 1, html: "<b/>")
             == Patch.createRawHTML(handle: 1, html: "<b/>"))
        #expect(Patch.destroyNode(handle: 1) == Patch.destroyNode(handle: 1))
    }

    @Test("Tree-structure opcodes equate by all positions")
    func structureEquality() {
        #expect(Patch.appendChild(parent: 1, child: 2)
             == Patch.appendChild(parent: 1, child: 2))
        #expect(Patch.insertBefore(parent: 1, child: 2, beforeChild: 3)
             == Patch.insertBefore(parent: 1, child: 2, beforeChild: 3))
        #expect(Patch.removeChild(parent: 1, child: 2)
             == Patch.removeChild(parent: 1, child: 2))
    }

    @Test("Mutation opcodes equate by all fields")
    func mutationEquality() {
        #expect(Patch.setAttribute(handle: 1, name: "class", value: "a")
             == Patch.setAttribute(handle: 1, name: "class", value: "a"))
        #expect(Patch.removeAttribute(handle: 1, name: "class")
             == Patch.removeAttribute(handle: 1, name: "class"))
        #expect(Patch.setProperty(handle: 1, name: "value", value: .string("x"))
             == Patch.setProperty(handle: 1, name: "value", value: .string("x")))
        #expect(Patch.removeProperty(handle: 1, name: "value")
             == Patch.removeProperty(handle: 1, name: "value"))
        #expect(Patch.setStyle(handle: 1, name: "color", value: "red")
             == Patch.setStyle(handle: 1, name: "color", value: "red"))
        #expect(Patch.removeStyle(handle: 1, name: "color")
             == Patch.removeStyle(handle: 1, name: "color"))
        #expect(Patch.setText(handle: 1, text: "hi")
             == Patch.setText(handle: 1, text: "hi"))
    }

    @Test("Event opcodes equate by all fields")
    func eventEquality() {
        #expect(Patch.addHandler(handle: 1, event: "click", handlerId: 7)
             == Patch.addHandler(handle: 1, event: "click", handlerId: 7))
        #expect(Patch.removeHandler(handle: 1, event: "click")
             == Patch.removeHandler(handle: 1, event: "click"))
    }

    @Test("Different opcodes never equate")
    func crossOpcodeInequality() {
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createText(handle: 1, text: "div"))
        #expect(Patch.appendChild(parent: 1, child: 2)
             != Patch.removeChild(parent: 1, child: 2))
    }
}
