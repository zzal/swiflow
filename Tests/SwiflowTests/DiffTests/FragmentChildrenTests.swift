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
}
