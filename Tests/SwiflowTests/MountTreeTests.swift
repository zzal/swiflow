// Tests/SwiflowTests/MountTreeTests.swift
import Testing
@testable import Swiflow

@Suite("MountTree")
struct MountTreeTests {
    @Test("MountNode stores handle and last-committed VNode")
    func storesHandleAndVNode() {
        let node = MountNode(handle: 42, vnode: .text("hi"))
        #expect(node.handle == 42)
        #expect(node.vnode == .text("hi"))
        #expect(node.children.isEmpty)
        #expect(node.handlerIds.isEmpty)
        #expect(node.parent == nil)
    }

    @Test("addChild wires parent pointer")
    func addChildWiresParent() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let child = MountNode(handle: 2, vnode: .text("c"))
        parent.addChild(child)
        #expect(parent.children.count == 1)
        #expect(parent.children[0] === child)
        #expect(child.parent === parent)
    }

    @Test("removeChild detaches and clears parent pointer")
    func removeChildDetaches() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let child = MountNode(handle: 2, vnode: .text("c"))
        parent.addChild(child)
        parent.removeChild(at: 0)
        #expect(parent.children.isEmpty)
        #expect(child.parent == nil)
    }

    @Test("insertChild at index wires parent pointer")
    func insertChildAtIndex() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let a = MountNode(handle: 2, vnode: .text("a"))
        let b = MountNode(handle: 3, vnode: .text("b"))
        let c = MountNode(handle: 4, vnode: .text("c"))
        parent.addChild(a)
        parent.addChild(c)
        parent.insertChild(b, at: 1)
        #expect(parent.children.map(\.handle) == [2, 3, 4])
        #expect(b.parent === parent)
    }

    @Test("handlerIds tracks event→handler mappings")
    func handlerIdsTracking() {
        let node = MountNode(handle: 1, vnode: .text("x"))
        node.handlerIds["click"] = 7
        node.handlerIds["input"] = 8
        #expect(node.handlerIds["click"] == 7)
        #expect(node.handlerIds["input"] == 8)
        #expect(node.handlerIds.count == 2)
    }
}
