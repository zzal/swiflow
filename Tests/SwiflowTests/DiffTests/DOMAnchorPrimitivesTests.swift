// Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — DOM-anchor primitives")
@MainActor
struct DOMAnchorPrimitivesTests {
    // Mount a VNode to a real MountNode tree so primitives have something to walk.
    private func mountTree(_ v: VNode) -> MountNode {
        var patches: [Patch] = []
        return mount(v, into: &patches, handles: HandleAllocator(), handlers: HandlerRegistry())
    }

    @Test("collectDOMRoots of an element is its own handle")
    func rootsOfElement() {
        let n = mountTree(.element(ElementData(tag: "div")))
        #expect(collectDOMRoots(n) == [n.handle])
    }

    @Test("collectDOMRoots descends through a fragment to its children")
    func rootsThroughFragment() {
        // ul(handle 0) > fragment(handle 1) > [text"a"(2), text"b"(3)]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .fragment([.text("a"), .text("b")])
        ])))
        #expect(collectDOMRoots(ul) == [ul.handle])
        let frag = ul.children[0]
        #expect(collectDOMRoots(frag) == [2, 3])
    }

    @Test("firstDOMHandle of an empty fragment is nil")
    func firstOfEmptyFragment() {
        let ul = mountTree(.element(ElementData(tag: "ul", children: [.fragment([])])))
        #expect(firstDOMHandle(ul.children[0]) == nil)
    }

    @Test("nextDOMAnchor after a fragment's last child ascends to the next real sibling")
    func anchorAscendsAcrossFragmentBoundary() {
        // ul > [ fragment[textA(2)], div(3) ]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .fragment([.text("a")]),
            .element(ElementData(tag: "div")),
        ])))
        let frag = ul.children[0]
        let textA = frag.children[0]
        // After textA (last in fragment) the next DOM node is the div (handle 3).
        #expect(nextDOMAnchor(after: textA) == 3)
    }

    @Test("nextDOMAnchor returns nil (append) at the true tail across an empty trailing fragment")
    func anchorTailWithEmptyFragment() {
        // ul > [ div(1), fragment[](2) ]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "div")),
            .fragment([]),
        ])))
        let div = ul.children[0]
        #expect(nextDOMAnchor(after: div) == nil)  // empty fragment after → append
    }
}
