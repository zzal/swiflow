// Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — children (indexed)")
struct IndexedChildrenTests {
    private func ul(_ texts: [String]) -> VNode {
        .element(ElementData(tag: "ul", children: texts.map { .text($0) }))
    }

    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }

    @Test("Same-length children with identical texts emit no patches")
    func sameLengthIdentical() {
        let u = diffPair(ul(["a", "b"]), ul(["a", "b"]))
        #expect(u.patches.isEmpty)
    }

    @Test("Same-length children with one changed text emits one setText")
    func sameLengthOneChanged() {
        let u = diffPair(ul(["a", "b"]), ul(["a", "B"]))
        // Old text "b" lives at handle 2 (ul=0, "a"=1, "b"=2).
        #expect(u.patches == [.setText(handle: 2, text: "B")])
    }

    @Test("Appending one child emits createText + appendChild")
    func appendOne() {
        let u = diffPair(ul(["a"]), ul(["a", "b"]))
        // ul=0, "a"=1; new "b" gets handle 2.
        #expect(u.patches == [
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Removing the last child emits removeChild + destroyNode")
    func removeLast() {
        let u = diffPair(ul(["a", "b"]), ul(["a"]))
        // "b" lives at handle 2; ul at 0.
        #expect(u.patches == [
            .removeChild(parent: 0, child: 2),
            .destroyNode(handle: 2),
        ])
    }

    @Test("Append at end with type change of existing child")
    func appendAndChange() {
        let u = diffPair(ul(["a"]), ul(["A", "b"]))
        // ul=0, "a"=1, new "b"=2.
        #expect(u.patches == [
            .setText(handle: 1, text: "A"),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Removing all children emits per-child removeChild+destroyNode")
    func removeAllChildren() {
        let u = diffPair(ul(["a", "b"]), ul([]))
        #expect(u.patches == [
            .removeChild(parent: 0, child: 1),
            .destroyNode(handle: 1),
            .removeChild(parent: 0, child: 2),
            .destroyNode(handle: 2),
        ])
    }

    @Test("Index-pair handles position-shifted text (no keys)")
    func positionShiftedText() {
        // ["a","b","c"] → ["b","c","a"] without keys: index-pair compares
        // a↔b (different → setText), b↔c (different → setText), c↔a
        // (different → setText). This is *correct under no-keys semantics*
        // (every index changed text); the keyed path (Task 17) does better.
        let u = diffPair(ul(["a", "b", "c"]), ul(["b", "c", "a"]))
        #expect(u.patches == [
            .setText(handle: 1, text: "b"),
            .setText(handle: 2, text: "c"),
            .setText(handle: 3, text: "a"),
        ])
    }

    @Test("Empty list → populated emits per-child create+appendChild")
    func emptyToPopulated() {
        let u = diffPair(ul([]), ul(["a", "b"]))
        // ul=0; "a" gets handle 1; "b" gets handle 2.
        #expect(u.patches == [
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Empty list → empty list emits no patches")
    func emptyToEmpty() {
        let u = diffPair(ul([]), ul([]))
        #expect(u.patches.isEmpty)
    }

    @Test("Insert in the middle of an existing list (no keys)")
    func insertMiddle() {
        // ["a","c"] → ["a","b","c"]. Index-pair compares a==a (no-op),
        // c→b (setText), then appends one new node (which will be the new
        // tail "c" with a fresh handle).
        let u = diffPair(ul(["a", "c"]), ul(["a", "b", "c"]))
        #expect(u.patches == [
            .setText(handle: 2, text: "b"),
            .createText(handle: 3, text: "c"),
            .appendChild(parent: 0, child: 3),
        ])
    }

    @Test("Cross-kind transition mid-list: text→element triggers destroy+create+insertBefore")
    func crossKindMidList() {
        // [text("a"), text("b")] → [element(span), text("b")]
        // Old children: ul=0, "a"=1, "b"=2.
        // Update on index 0: text→element triggers the default arm:
        //   destroyNode(1), createElement(3, "span")
        //   update returns the fresh MountNode → mounted.replaceChild(at:0)
        //   then insertBefore(0, 3, beforeChild: 2) to position it before "b".
        // Update on index 1: text("b")→text("b") is a no-op.
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.element(ElementData(
            tag: "ul",
            children: [.text("a"), .text("b")]
        ))
        let next = VNode.element(ElementData(
            tag: "ul",
            children: [.element(ElementData(tag: "span")), .text("b")]
        ))
        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
        #expect(u.patches == [
            .destroyNode(handle: 1),
            .createElement(handle: 3, tag: "span"),
            .insertBefore(parent: 0, child: 3, beforeChild: 2),
        ])
        // Parent pointer wiring sanity: the new MountNode's parent is the ul.
        #expect(u.newMountTree.children.count == 2)
        #expect(u.newMountTree.children[0].handle == 3)
        #expect(u.newMountTree.children[1].handle == 2)
    }

    @Test("Cross-kind transition at tail: text→element triggers destroy+create+appendChild")
    func crossKindAtTail() {
        // [text("a"), text("b")] → [text("a"), element(span)]
        // Old children: ul=0, "a"=1, "b"=2.
        // Index 0: text("a")→text("a") no-op.
        // Index 1: text→element via default arm:
        //   destroyNode(2), createElement(3, "span")
        //   replaceChild(at:1); i+1==2 == oldCount → appendChild (no anchor).
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.element(ElementData(
            tag: "ul",
            children: [.text("a"), .text("b")]
        ))
        let next = VNode.element(ElementData(
            tag: "ul",
            children: [.text("a"), .element(ElementData(tag: "span"))]
        ))
        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
        #expect(u.patches == [
            .destroyNode(handle: 2),
            .createElement(handle: 3, tag: "span"),
            .appendChild(parent: 0, child: 3),
        ])
    }
}
