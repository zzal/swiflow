// Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — fragment children")
@MainActor
struct FragmentChildrenTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }
    private func mountOnly(_ a: VNode) -> DiffResult {
        diff(mounted: nil, next: a, handles: HandleAllocator(), handlers: HandlerRegistry())
    }

    @Test("First mount: a fragment child's nodes append to the fragment's real parent")
    func firstMountFragment() {
        // div(0) > fragment(1) > [text"a"(2), text"b"(3)]
        let r = mountOnly(.element(ElementData(tag: "div", children: [
            .fragment([.text("a"), .text("b")])
        ])))
        #expect(r.patches == [
            .createElement(handle: 0, tag: "div"),
            .createText(handle: 2, text: "a"),
            .createText(handle: 3, text: "b"),
            .appendChild(parent: 0, child: 2),
            .appendChild(parent: 0, child: 3),
        ])
    }

    @Test("Mid-list fragment emptying preserves a later sibling's handle (the dialog/toast bug)")
    func midListFragmentEmptyingPreservesSibling() {
        // div > [ p(stable), fragment[span], p(stable-after) ]  →  fragment goes empty
        let full = VNode.element(ElementData(tag: "div", children: [
            .element(ElementData(tag: "p")),
            .fragment([.element(ElementData(tag: "span"))]),
            .element(ElementData(tag: "p")),
        ]))
        let empty = VNode.element(ElementData(tag: "div", children: [
            .element(ElementData(tag: "p")),
            .fragment([]),
            .element(ElementData(tag: "p")),
        ]))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: full, handles: handles, handlers: handlers)
        // Handles: div0, p1, frag2, span3, p4.
        let afterBefore = m.newMountTree.children[2].handle
        let u = diff(mounted: m.newMountTree, next: empty, handles: handles, handlers: handlers)
        // The span (3) is removed; the trailing <p> keeps handle 4 — NOT recreated.
        #expect(u.patches == [
            .removeChild(parent: 0, child: 3),
            .destroyNode(handle: 3),
        ])
        #expect(u.newMountTree.children[2].handle == afterBefore)
        #expect(u.newMountTree.children[2].handle == 4)
    }

    @Test("Empty fragment refilling inserts before the correct following sibling")
    func emptyFragmentRefilling() {
        // div > [ fragment[](1), div"tail"(2) ]  →  fragment gains a span
        let empty = VNode.element(ElementData(tag: "div", children: [
            .fragment([]),
            .element(ElementData(tag: "div")),
        ]))
        let full = VNode.element(ElementData(tag: "div", children: [
            .fragment([.element(ElementData(tag: "span"))]),
            .element(ElementData(tag: "div")),
        ]))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: empty, handles: handles, handlers: handlers)
        // Handles: div0, frag1, div2.
        let u = diff(mounted: m.newMountTree, next: full, handles: handles, handlers: handlers)
        // New span (handle 3) must insertBefore the tail div (2), not append.
        #expect(u.patches == [
            .createElement(handle: 3, tag: "span"),
            .insertBefore(parent: 0, child: 3, beforeChild: 2),
        ])
    }

    @Test("Keyed list with a fragment sibling: reordering keyed elements keeps handles")
    func keyedListWithFragmentSibling() {
        // ul > [ li#a(key a), fragment[li x], li#b(key b) ] → swap a and b
        func tree(_ order: [String]) -> VNode {
            .element(ElementData(tag: "ul", children: [
                .element(ElementData(tag: "li", key: order[0])),
                .fragment([.element(ElementData(tag: "li"))]),
                .element(ElementData(tag: "li", key: order[1])),
            ]))
        }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: tree(["a", "b"]), handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: tree(["b", "a"]), handles: handles, handlers: handlers)
        // No createElement — both keyed <li>s are reused (their handles preserved).
        #expect(!u.patches.contains { if case .createElement = $0 { return true }; return false })
    }

    @Test("Keyed list with TWO fragment siblings: keyed reorder re-mounts neither fragment's child")
    func keyedListWithTwoFragmentSiblings() {
        // ul > [ li#a, fragmentA[span], fragmentB[b], li#c ]  → swap the keyed li's.
        // The two fragments are positionally stable and must each be reused
        // (their children span/b NOT recreated). Before the position-stable
        // bucket key they collide on "__noKey_structural" and one is re-mounted.
        func tree(_ order: [String]) -> VNode {
            .element(ElementData(tag: "ul", children: [
                .element(ElementData(tag: "li", key: order[0])),
                .fragment([.element(ElementData(tag: "span"))]),
                .fragment([.element(ElementData(tag: "b"))]),
                .element(ElementData(tag: "li", key: order[1])),
            ]))
        }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: tree(["a", "c"]), handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: tree(["c", "a"]), handles: handles, handlers: handlers)
        #expect(!u.patches.contains { if case .createElement = $0 { return true }; return false })
    }
}
