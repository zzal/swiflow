// Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — unmanaged children escape hatch")
@MainActor
struct UnmanagedChildrenTests {
    private func data(_ node: VNode) -> ElementData? {
        if case .element(let d) = node { return d }
        return nil
    }

    @Test(".unmanagedChildren() sets the flag on an element") func modifierSetsFlag() {
        let node = VNode.element(ElementData(tag: "div")).unmanagedChildren()
        #expect(data(node)?.managesOwnChildren == true)
    }

    @Test("a plain element does not have the flag") func defaultIsFalse() {
        #expect(data(.element(ElementData(tag: "div")))?.managesOwnChildren == false)
    }

    @Test("equality distinguishes the flag") func equalityDistinguishesFlag() {
        let plain = VNode.element(ElementData(tag: "div"))
        let flagged = VNode.element(ElementData(tag: "div")).unmanagedChildren()
        #expect(plain != flagged)
    }

    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("initial children mount once (same patches as a managed element)") func mountsInitialChildrenOnce() {
        let r = diff(mounted: nil,
                     next: VNode.element(ElementData(tag: "div", children: [.text("a")])).unmanagedChildren(),
                     handles: HandleAllocator(), handlers: HandlerRegistry())
        #expect(r.patches == [
            .createElement(handle: 0, tag: "div"),
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
        ])
    }

    @Test("a re-render with different children emits NO child patches") func reRenderSkipsChildren() {
        let a = VNode.element(ElementData(tag: "div", children: [.text("a")])).unmanagedChildren()
        let b = VNode.element(ElementData(tag: "div", children: [.text("b"), .text("c")])).unmanagedChildren()
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [])   // shell unchanged, children left alone
    }

    @Test("the element shell stays reactive (its own attributes still diff)") func shellStaysReactive() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"], children: [.text("a")])).unmanagedChildren()
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "y"], children: [.text("a")])).unmanagedChildren()
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [.setAttribute(handle: 0, name: "class", value: "y")])
    }

    @Test("regression: a managed element still reconciles its children") func managedStillReconciles() {
        let a = VNode.element(ElementData(tag: "div", children: [.text("a")]))
        let b = VNode.element(ElementData(tag: "div", children: [.text("b")]))
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [.setText(handle: 1, text: "b")])
    }
}
