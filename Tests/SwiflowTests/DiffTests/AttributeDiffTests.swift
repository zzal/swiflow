// Tests/SwiflowTests/DiffTests/AttributeDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — attributes")
struct AttributeDiffTests {

    /// Convenience: mount `initial`, then diff `next` against the result.
    /// Returns only the *second* diff's patches (not the first-mount patches).
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let update = diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers)
        return update.patches
    }

    @Test("Adding an attribute emits setAttribute")
    func addAttribute() {
        let a = VNode.element(ElementData(tag: "div"))
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        #expect(patches(from: a, to: b) == [
            .setAttribute(handle: 0, name: "class", value: "x"),
        ])
    }

    @Test("Removing an attribute emits removeAttribute")
    func removeAttribute() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        let b = VNode.element(ElementData(tag: "div"))
        #expect(patches(from: a, to: b) == [
            .removeAttribute(handle: 0, name: "class"),
        ])
    }

    @Test("Changing an attribute emits setAttribute with the new value")
    func changeAttribute() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "y"]))
        #expect(patches(from: a, to: b) == [
            .setAttribute(handle: 0, name: "class", value: "y"),
        ])
    }

    @Test("Unchanged attributes emit no patches")
    func unchangedNoPatches() {
        let attrs = ["class": "x", "id": "main"]
        let a = VNode.element(ElementData(tag: "div", attributes: attrs))
        let b = VNode.element(ElementData(tag: "div", attributes: attrs))
        #expect(patches(from: a, to: b).isEmpty)
    }
}
