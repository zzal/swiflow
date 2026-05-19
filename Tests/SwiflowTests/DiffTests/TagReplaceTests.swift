// Tests/SwiflowTests/DiffTests/TagReplaceTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — tag replace")
@MainActor
struct TagReplaceTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("Different tag at root destroys and recreates with new handle")
    func differentTagReplaces() {
        let (m, u) = diffPair(
            .element(ElementData(tag: "div")),
            .element(ElementData(tag: "span"))
        )
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createElement(handle: m.newMountTree.handle + 1, tag: "span"),
        ])
        #expect(u.newMountTree.handle != m.newMountTree.handle)
    }

    @Test("Tag replace destroys all descendants too")
    func tagReplaceDestroysDescendants() {
        let (m, u) = diffPair(
            .element(ElementData(tag: "ul", children: [.text("a"), .text("b")])),
            .element(ElementData(tag: "ol"))
        )
        // Children destroyed first (post-order), then the parent, then the
        // fresh element is created with a brand-new (never-recycled) handle.
        let oldRoot = m.newMountTree.handle
        let childA = m.newMountTree.children[0].handle
        let childB = m.newMountTree.children[1].handle
        let newRoot = u.newMountTree.handle
        #expect(newRoot != oldRoot && newRoot != childA && newRoot != childB)
        #expect(u.patches == [
            .destroyNode(handle: childA),
            .destroyNode(handle: childB),
            .destroyNode(handle: oldRoot),
            .createElement(handle: newRoot, tag: "ol"),
        ])
    }

    @Test("Tag replace removes handlers from the registry")
    func tagReplaceCleansRegistry() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let m = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        _ = diff(
            mounted: m.newMountTree,
            next: .element(ElementData(tag: "div")),
            handles: handles,
            handlers: handlers
        )
        #expect(handlers.handler(forID: h.id) == nil)
    }
}
