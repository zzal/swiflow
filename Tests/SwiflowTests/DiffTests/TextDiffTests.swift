// Tests/SwiflowTests/DiffTests/TextDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — text and rawHTML")
struct TextDiffTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("Identical text emits no patches")
    func identicalText() {
        let (_, u) = diffPair(.text("hi"), .text("hi"))
        #expect(u.patches.isEmpty)
    }

    @Test("Different text emits setText, mount tree retains handle")
    func differentText() {
        let (m, u) = diffPair(.text("hi"), .text("bye"))
        let rootHandle = m.newMountTree.handle
        #expect(u.patches == [.setText(handle: rootHandle, text: "bye")])
        #expect(u.newMountTree.handle == rootHandle)
        #expect(u.newMountTree.vnode == .text("bye"))
    }

    @Test("Different rawHTML emits setRawHTML, mount tree retains handle")
    func differentRawHTML() {
        let (m, u) = diffPair(.rawHTML("<b/>"), .rawHTML("<i/>"))
        #expect(u.patches == [
            .setRawHTML(handle: m.newMountTree.handle, html: "<i/>"),
        ])
    }

    @Test("Text→element at root emits destroy+create, new mount tree has fresh handle")
    func textToElementAtRoot() {
        let (m, u) = diffPair(.text("hi"), .element(ElementData(tag: "span")))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createElement(handle: m.newMountTree.handle + 1, tag: "span"),
        ])
        #expect(u.newMountTree.handle == m.newMountTree.handle + 1)
    }

    @Test("Element→text at root emits destroy+create")
    func elementToTextAtRoot() {
        let (m, u) = diffPair(.element(ElementData(tag: "span")), .text("hi"))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createText(handle: m.newMountTree.handle + 1, text: "hi"),
        ])
    }

    @Test("Text→rawHTML at root emits destroy+create")
    func textToRawHTMLAtRoot() {
        let (m, u) = diffPair(.text("hi"), .rawHTML("<b/>"))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createRawHTML(handle: m.newMountTree.handle + 1, html: "<b/>"),
        ])
    }
}
