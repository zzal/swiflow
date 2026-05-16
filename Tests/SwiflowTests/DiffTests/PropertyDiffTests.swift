// Tests/SwiflowTests/DiffTests/PropertyDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — properties")
struct PropertyDiffTests {
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        return diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers).patches
    }

    @Test("Adding a property emits setProperty")
    func addProperty() {
        let a = VNode.element(ElementData(tag: "input"))
        let b = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "value", value: .string("x")),
        ])
    }

    @Test("Removing a property emits removeProperty")
    func removeProperty() {
        let a = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        let b = VNode.element(ElementData(tag: "input"))
        #expect(patches(from: a, to: b) == [
            .removeProperty(handle: 0, name: "value"),
        ])
    }

    @Test("Changing a property emits setProperty with new value")
    func changeProperty() {
        let a = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        let b = VNode.element(ElementData(tag: "input", properties: ["value": .string("y")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "value", value: .string("y")),
        ])
    }

    @Test("Property type change emits setProperty")
    func changePropertyType() {
        let a = VNode.element(ElementData(tag: "input", properties: ["checked": .bool(true)]))
        let b = VNode.element(ElementData(tag: "input", properties: ["checked": .string("yes")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "checked", value: .string("yes")),
        ])
    }
}
