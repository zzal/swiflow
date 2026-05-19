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

@Suite("Mount-tree consistency after diff")
struct MountTreeConsistencyTests {

    /// Walk a `MountNode` and produce the VNode it represents (i.e., the
    /// committed `vnode` recursively replaced by its children's committed
    /// `vnode`s). For elements, the returned VNode preserves the latest
    /// children structure but uses each child's stored `vnode`.
    private func committedVNode(_ node: MountNode) -> VNode {
        switch node.vnode {
        case .text, .rawHTML, .component:
            // .component is a Phase 3 anchor — the round-trip tests in
            // this file don't exercise the .component case, so passing
            // through the stored vnode is sufficient. Tasks 4–5 add their
            // own mount/update tests for the component path.
            return node.vnode
        case .element(let data):
            let kids = node.children.map(committedVNode)
            return .element(ElementData(
                tag: data.tag,
                key: data.key,
                attributes: data.attributes,
                properties: data.properties,
                style: data.style,
                handlers: data.handlers,
                children: kids
            ))
        }
    }

    private func roundTrip(_ a: VNode, _ b: VNode) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        #expect(committedVNode(m.newMountTree) == a, "first mount must reconstruct input")
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        #expect(committedVNode(u.newMountTree) == b, "post-diff mount tree must reconstruct b")
    }

    @Test("Consistency: text → text")
    func textToText() {
        roundTrip(.text("a"), .text("b"))
    }

    @Test("Consistency: element with attribute change")
    func attrChange() {
        roundTrip(
            .element(ElementData(tag: "div", attributes: ["class": "x"])),
            .element(ElementData(tag: "div", attributes: ["class": "y"]))
        )
    }

    @Test("Consistency: list of children (indexed)")
    func childrenIndexed() {
        roundTrip(
            .element(ElementData(tag: "ul", children: [.text("a"), .text("b")])),
            .element(ElementData(tag: "ul", children: [.text("a"), .text("B"), .text("c")]))
        )
    }

    @Test("Consistency: list of children (keyed reorder)")
    func childrenKeyedReorder() {
        let withKeys: ([String]) -> VNode = { keys in
            .element(ElementData(
                tag: "ul",
                children: keys.map {
                    .element(ElementData(tag: "li", key: $0, children: [.text($0)]))
                }
            ))
        }
        roundTrip(withKeys(["a", "b", "c"]), withKeys(["c", "a", "b"]))
    }

    @Test("Mount tree consistency: keyed empty → populated")
    func keyedEmptyToPopulated() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.element(ElementData(tag: "ul", children: []))
        let next = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "li", key: "b")),
        ]))
        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
        // Mount tree structurally equals the new VNode (modulo handles).
        let finalKeys: [String] = u.newMountTree.children.map { keyOf($0) }
        #expect(finalKeys == ["a", "b"])
        // Each child's parent pointer references the root.
        for child in u.newMountTree.children {
            #expect(child.parent === u.newMountTree)
        }
    }

    @Test("Mount tree consistency: keyed populated → empty")
    func keyedPopulatedToEmpty() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "li", key: "b")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: []))
        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
        #expect(u.newMountTree.children.isEmpty)
    }

    @Test("Consistency: tag replace")
    func tagReplace() {
        roundTrip(
            .element(ElementData(tag: "div")),
            .element(ElementData(tag: "span"))
        )
    }
}
