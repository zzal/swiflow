// Tests/SwiflowTests/DiffTests/RawHTMLUpdateTests.swift
import Testing
@testable import Swiflow

@Suite("rawHTML update emits setRawHTML (never setProperty(innerHTML))")
struct RawHTMLUpdateTests {
    @Test("rawHTML value change emits a single setRawHTML patch")
    func updatesViaSetRawHTML() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.rawHTML("<b>old</b>")
        let next = VNode.rawHTML("<b>new</b>")

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        #expect(u.patches == [.setRawHTML(handle: 0, html: "<b>new</b>")])
    }

    @Test("rawHTML diff never emits setProperty named \"innerHTML\"")
    func neverEmitsHtmlPropertyName() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.rawHTML("a")
        let next = VNode.rawHTML("b")

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        for patch in u.patches {
            if case .setProperty(_, let name, _) = patch {
                Issue.record("rawHTML update produced setProperty(\"\(name)\")")
            }
        }
    }
}
