// Tests/SwiflowTests/DiffTests/StyleDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — styles")
@MainActor
struct StyleDiffTests {
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        return diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers).patches
    }

    @Test("Adding a style declaration emits setStyle")
    func addStyle() {
        let a = VNode.element(ElementData(tag: "div"))
        let b = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        #expect(patches(from: a, to: b) == [
            .setStyle(handle: 0, name: "color", value: "red"),
        ])
    }

    @Test("Removing a style declaration emits removeStyle")
    func removeStyle() {
        let a = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        let b = VNode.element(ElementData(tag: "div"))
        #expect(patches(from: a, to: b) == [
            .removeStyle(handle: 0, name: "color"),
        ])
    }

    @Test("Changing a style declaration emits setStyle with new value")
    func changeStyle() {
        let a = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        let b = VNode.element(ElementData(tag: "div", style: ["color": "blue"]))
        #expect(patches(from: a, to: b) == [
            .setStyle(handle: 0, name: "color", value: "blue"),
        ])
    }
}
